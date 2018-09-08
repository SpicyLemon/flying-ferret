package flyingferret;
################################################################################
# 
# flyingferret.pm
# 
# Author:      Danny Wedul
# Date:        June 29, 2010
#              
# Description: This module is used to transform input into links, rolls, and decisions etc..
#              It is inspired by the flyingferret bot found in the xkcd irc channel, 
#              #xkcd on irc.foonetic.net.
#              The documentation for that bot can be found here:
#              http://www.chiliahedron.com/ferret/
#              
# Revisions:   August 8, 2018: Change or matching to be before dice rolling.
#              
################################################################################
use strict;
use warnings;
use URI::Escape;        #imports uri_escape

our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
BEGIN {
   require Exporter;
   our @ISA = qw(Exporter);
   our @EXPORT = qw();  #nothing should be exported by default
   our @EXPORT_OK = qw(transform);
}

#Any searches that just need to be uri encoded and appended
#to a search uri can be added to this list.
my %standard_links = (
   google => 'http://www.google.com/search?q=',
   bing   => 'http://www.bing.com/search?q=',
   imdb   => 'http://www.imdb.com/find?s=all&q=',
   wiki   => 'http://en.wikipedia.org/wiki/',
   alpha  => 'http://www.wolframalpha.com/input/?i=',
   image  => 'http://www.google.com/images?q=',
   gimage => 'http://www.google.com/images?q=',
   bimage => 'http://www.bing.com/images/search?q=',
   imgur  => 'https://imgur.com/?q=',
   giffy  => 'https://giphy.com/search/',
   amazon => 'http://www.amazon.com/s/ref=nb_sb_noss?url=search-alias%3Daps&field-keywords=',
   ebay   => 'http://shop.ebay.com/?_nkw=',
   lmgtfy => 'http://lmgtfy.com/?q=',
);

#If there is a special mobile link for a search in the standard links hash, you can
#add that information here.  If a mobile link is asked for, and there isn't an entry
#in this hash, it will use the link defined in the standard links hash.
my %mobile_links = (
   imdb   => 'http://m.imdb.com/find?q=',
   alpha  => 'http://m.wolframalpha.com/input/?i=',
);



##############################################################
# Sub          transform
# Usage        my $output_list_ref = flyingferret::transform($input, $mobile_flag);
#              
# Parameters   $input = the string that you wish to transform
#              $mobile_flag = an optional flag. If set to true, mobile links will
#                             be used instead of the standard ones.
#              
# Description  Processes input to do all stuff flyingferret should do
#              This is pretty much the only sub that you should be calling
#              from outside this module.
#              
# Returns      a reference to a list of strings
##############################################################
sub transform {
   my $input = shift || '';
   my $mobile_flag = shift || '';
   
   #set up the links to use
   my %links = ();
   foreach my $k (keys %standard_links) {
      $links{$k} = ($mobile_flag && $mobile_links{$k}) 
                 ? $mobile_links{$k}
                 : $standard_links{$k}
                ;
   }
      
   my @retval = ();
   
   my $lmgtfy_flag = 0;
   
   #first, look for standard links
   foreach my $k (keys %links) {
      if ($input =~ m{$k://}i) {
         my @new_lines = @{transform_link($input, $k, $links{$k})};
         if ($#new_lines >= 0) {
            push (@retval, @new_lines);
            if ($k eq 'lmgtfy') {
               $lmgtfy_flag = 1;
            }
         }
      }
   }
   #Now look for the links that need a little special attention
   if ($input =~ m{xkcd://}i) {
      push (@retval, @{transform_xkcd($input)});
   }
   if ($input =~ m{trope://}i) {
      push (@retval, @{transform_trope($input)});
   }
   if ($input =~ m{bash://}i) {
      push (@retval, @{transform_bash($input)});
   }
   if ($input =~ m{qdb://}i) {
      push (@retval, @{transform_qdb($input)});
   }
   if ($input =~ m{xkcdb://}i) {
      push (@retval, @{transform_qdb($input)});
   }
   
   #now, if we don't have anything yet, check for the other stuff
   if ($#retval >= 0) {
      #we're set, nothing to do here
   }
   #check for 'or'
   elsif ($input =~ m{\bor\b}i) {
      push (@retval, @{transform_or($input)});
   }
   #check for rolls
   elsif ($input =~ m{d\d}i) {   #matches digit, 'd', digit
      push (@retval, @{transform_rolls($input)});
   }
   #lastly, check for a question mark at the end of the line
   elsif ($input =~ m{\?\s*$}i) {
      push (@retval, @{transform_yes_no($input)});
   }
   
   #add a nice message if all we've got is a lmgtfy flag
   if ($lmgtfy_flag && $#retval == 0) {
      push (@retval, 'You are not being automatically redirected since you '.
                     'probably just want this link to give to someone else.');
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_link
# Usage        my $output_list_ref = transform_link($input, $tag, $base_url);
#              
# Parameters   $input = the string that you wish to transform
#              $tag = the tag in the input signifying a link (i.e. 'google', 'qdb')
#                    this is going in a regex, so it should probably be just letters.
#              $base_url = the beginning of the url to return
#              
# Description  Attempts to transform the input into a link. This is very generic.
#              It makes sure the $input has $tag in it, followed, somewhere, by '://'
#              it grabs everything after the last '://', uri encodes it, and appends it
#              to $base_url
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_link {
   my $input = shift;
   my $tag = shift;
   my $base_url = shift;
   
   my @retval = ();
    
   if ($input =~ m{$tag.*://(.*)$}igx) {
      my $search = $1;
      $search =~ s/^\s+//;
      $search =~ s/\s+$//;
      push (@retval, $base_url.uri_escape($search));
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_trope
# Usage        my $output_list_ref = transform_trope($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a TV Tropes link
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_trope {
   my $input = shift;
   my $tag = 'trope';
   my $base_url = 'http://tvtropes.org/pmwiki/pmwiki.php/Main/';
   
   my @retval = ();
    
   if ($input =~ m{$tag.*://(.*)$}igx) {
      my $search = $1;
      #get rid of anything that's not a letter, number or space
      $search =~ s/[^a-zA-Z0-9 ]//g;
      my $trope = '';
      #split it by word, capitalize the first letter and lowercase the rest
      foreach my $word (split(/\s+/, $search)) {
         $word =~ s{^(\w)(\w*)$}{\u$1\L$2};
         $trope .= $word;
      }
      push (@retval, $base_url.uri_escape($trope));
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_xkcd
# Usage        my $output_list_ref = transform_xkcd($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a xkcd comic links
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_xkcd {
   my $input = shift;
   my $tag = 'xkcd';
   
   my @retval = ();
    
   if ($input =~ m{$tag.*://(.*)$}igx) {
      my $search = $1;
      #If it's only numbers, return the link to that numbered comic
      if ($search =~ /^\d+(?:\s+\d+)*$/) {
         #split it by numbers, and add a link to each
         foreach my $num (split(/\s+/, $search)) {
            push (@retval, 'http://xkcd.com/'.$num.'/');
         }
      }
      else {
         #return a link to the google search page for xkcd.
         my $action = 'http://www.google.com/cse';
         my %params = (
            cx => '012652707207066138651:zudjtuwe28q',
            ie => 'UTF-8',
            siteurl => 'www.xkcd.com/',
            q  => $search,
         );
         my @pairs = ();
         foreach my $k (keys %params) {
            push (@pairs, $k.'='.uri_escape($params{$k}));
         }
         my $google_url = $action.'?'.join('&', @pairs);
         push (@retval, $google_url);
      }
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_bash
# Usage        my $output_list_ref = transform_bash($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a bash.org
#              quote link
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_bash {
   my $input = shift;
   
   my @retval = ();
   
   if ($input =~ m{bash.*://(.*)$}igx) {
      my $search = $1;
      $search =~ s/^\s+//;
      $search =~ s/\s+$//;
      if ($search =~ m{^\d+$}) {
         push (@retval, 'http://www.bash.org/?quote='.$search);
      }
      else {
         push (@retval, 'http://www.bash.org/?sort=0&show=25&search='.$search);
      }
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_qdb
# Usage        my $output_list_ref = transform_qdb($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a xkcdb link
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_qdb {
   my $input = shift;
   
   my @retval = ();
   
   if ($input =~ m{(?:qdb|xkcdb).*://(.*)$}igx) {
      my $search = $1;
      $search =~ s/^\s+//;
      $search =~ s/\s+$//;
      if ($search =~ m{^\d+$}) {
         push (@retval, 'http://www.xkcdb.com/?'.$search);
      }
      else {
         push (@retval, 'http://www.xkcdb.com/?search='.$search);
      }
   }
   
   return \@retval;
}

##############################################################
# Sub          transform_rolls
# Usage        my $output_list_ref = transform_rolls($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a the desired
#              dice rolls
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_rolls {
   my $input = shift;
   
   my @retval = ();
   
   #this is intended to match d6 2d20 2d10+1 3d6-5 d100+3 etc.
   my @setups = ($input =~ m{[^\dd]*?(\d*d\d+(?:[+|-]\d+)?)}ig);
   
   my $grand_total = 0;
   foreach my $setup (@setups) {
      #get rid of any leading junk and trailing whitespace
      $setup =~ s{^[^\dd]*}{};
      $setup =~ s{\s+$}{};
      #split it into it's important parts.
      my $count = 1;
      my $faces = 1;
      my $modifier = 0;
      if ($setup =~ m{^(\d+)}) {
         $count = $1;
      }
      if ($setup =~ m{d(\d+)}) {
         $faces = $1;
      }
      if ($setup =~ m{([+-])(\d+)$}) {
         my $sign = $1;
         $modifier = $2;
         if ($sign eq '-') {
            $modifier = '-'.$modifier;
         }
      }
      #do the rolls
      my ($total, $string) = roll_dice($count, $faces, $modifier);
      #handle the output
      $grand_total += $total;
      push (@retval, $string);
   }
   
   #if there was more than one setup, add in the grand total
   if ($#setups > 0) {
      push (@retval, 'grand total: '.$grand_total);
   }
   
   return \@retval;
}

##############################################################
# Sub          roll_dice
# Usage        my ($total, $string) = roll_dice($count, $faces, $modifier);
#              
# Parameters   $count = the number of times to roll the dice
#              $faces = the number of faces on the dice to use
#              $modifier = an amount to add to the final total (may be negative)
#              
# Description  Rolls a die with $faces faces $count times then adds the
#              $modifier.  This puts together both a total and a string explaining
#              how it got to the total.
#              
# Returns      Two values in an array.
#                 The first is the total
#                 The second is the string explaining the total
##############################################################
sub roll_dice {
   my $count = shift || 0;
   my $faces = shift || 1;
   my $modifier = shift || 0;
   
   my $total = $modifier;
   
   #add a plus sign to the modifier if it's positive
   #this is for later string use.
   if ($modifier > 0) {
      $modifier = '+'.$modifier;
   }
   
   #do the rolls and finish the total
   my @rolls = ();
   foreach (1..$count) {
      my $roll = int(rand($faces))+1;
      $total += $roll;
      push (@rolls, $roll);
   }
   
   #put together the string
   #it should end up like this:
   #8d6+2 = 31: 3, 1, 2, 5, 6, 6, 4, 2  (+2)
   my $string = $count.'d'.$faces;
   if ($modifier) {
      $string .= $modifier;
   }   
   $string .= ' = '.$total.': '.join(', ', @rolls);
   if ($modifier) {
      $string .= '  ('.$modifier.')';
   }
   
   return ($total, $string);
}

##############################################################
# Sub          transform_or
# Usage        my $output_list_ref = transform_or($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into one of the 
#              options given in the input.
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_or {
   my $input = shift;
   
   my @options = ();
   
   if (int(rand(100)) == 1) {
      #There's a 1% chance to get one of these answers
      @options = ( 'Neither', 'Both', "Doesn't matter to me" );
   }
   else {
         
      if ($input =~ m{\<or\>}i) {
         @options = ($input =~ m{ (.+?)   (?: \<or\> | $ ) }igx);
      }
      else {
         @options = ($input =~ m{ (.+?)   (?: \bor\b | $ ) }igx);
      }
   }
   
   my $retval = $options[int(rand(scalar @options))];
   $retval =~ s{^\s+}{};
   $retval =~ s{[\s\?\.]+$}{};
   
   return [ $retval ];
}

##############################################################
# Sub          transform_yes_no
# Usage        my $output_list_ref = transform_yes_no($input);
#              
# Parameters   $input = the string that you wish to transform
#              
# Description  Attempts to transform the input into a yes/no-ish answer
#              
# Returns      a reference to a list of strings
##############################################################
sub transform_yes_no {
   my $input = shift;
   
   my @retval = ();
   
   my @possibilities = (
      'Yes', 'Probably', 'Sure', 'Definitely',
      'No',  'Absolutely not!', 'Nope',
      'Maybe', 'Possibly', '42', 'Sort of',
   );
   
   if (int(rand(10)) == 1) {
      #10% chance to add this one to the possibilities
      push (@possibilities, 
            'Rub your belly three times and ask again.',
            'Light some candles and ask again.',
      );
   }
   
   if ($input =~ m{\?\s*$}) {
      if ($input =~ m{^(?:how|why|what|who|when|where)}i) {
         push (@retval, "I don't know.");
      }
      else {
         push (@retval, $possibilities[int(rand(scalar @possibilities))]);
      }
   }
   
   return \@retval;
}

1;