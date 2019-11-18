package flyingferret;
################################################################################
#
# flyingferret.pm
#
# Author:      Danny Wedul
# Date:        June 29, 2010
#
# Description: This module is used to transform input into links, rolls, and decisions etc..
#              It is inspired by the flyingferret bot once spotted in the xkcd irc channel,
#              #xkcd now on irc.slashnet.org.
#
# Revisions:   August 8, 2018: Change or matching to be before dice rolling.
#              September 11, 2018: Switch to use https where available.
#                                  Have the xkcd link creator pay attention to the mobile flag
#                                  Allow ,.. to be used as a replacement for ://
#              January 9, 2019: Add ability to roll pigs.
#              November 17, 2018: Add ability to get x random elements of a list.
#
################################################################################
use strict;
use warnings;
use URI::Escape;        #imports uri_escape
use List::Util qw(shuffle);

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
   google => 'https://www.google.com/search?q=',
   bing   => 'https://www.bing.com/search?q=',
   imdb   => 'https://www.imdb.com/find?s=all&q=',
   wiki   => 'https://en.wikipedia.org/wiki/',
   alpha  => 'https://www.wolframalpha.com/input/?i=',
   image  => 'https://www.google.com/images?q=',
   gimage => 'https://www.google.com/images?q=',
   bimage => 'https://www.bing.com/images/search?q=',
   imgur  => 'https://imgur.com/?q=',
   giffy  => 'https://giphy.com/search/',
   amazon => 'https://www.amazon.com/s/ref=nb_sb_noss?url=search-alias%3Daps&field-keywords=',
   ebay   => 'https://shop.ebay.com/?_nkw=',
   lmgtfy => 'https://lmgtfy.com/?q=',
);

#If there is a special mobile link for a search in the standard links hash, you can
#add that information here.  If a mobile link is asked for, and there isn't an entry
#in this hash, it will use the link defined in the standard links hash.
my %mobile_links = (
   imdb   => 'https://m.imdb.com/find?q=',
   alpha  => 'https://m.wolframalpha.com/input/?i=',
);

#variable name is short for "link regex".
#This is used in the regexes that test to see if users want links created.
my $lr = qr^(?:://|,\.\.)^;


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

   #first, look for standard links
   foreach my $k (keys %links) {
      if ($input =~ m{$k$lr}i) {
         push (@retval, @{transform_link($input, $k, $links{$k})});
      }
   }
   #Now look for the links that need a little special attention
   if ($input =~ m{xkcd$lr}i) {
      push (@retval, @{transform_xkcd($input, $mobile_flag)});
   }
   if ($input =~ m{trope$lr}i) {
      push (@retval, @{transform_trope($input)});
   }
   if ($input =~ m{bash$lr}i) {
      push (@retval, @{transform_bash($input)});
   }
   if ($input =~ m{(qdb|xkcdb)$lr}i) {
      push (@retval, @{transform_qdb($input)});
   }

   #now, if we don't have anything yet, check for the other stuff
   if ($#retval >= 0) {
      #we're set, nothing to do here
   }
   #First look for the complex thing of getting stuff from a list of stuff.
   # Optional "select" "get" or "give me" <count> optional "random" <thing type> optional "from in of" <things>
   # Examples:
   #  Give me 3 random names from Danny, George, Lynne, Mike, Sam, Paul, Josh
   #  10 numbers 1-100
   elsif ($input =~ m{^\s*(?:(?:select|get|give me)\s+)?(\d+)\s+(?:(?:random)\s+)?(\w+.*?)\s+(?:(?:from|in|of)\s+)?(.*)\.?\s*$}i) {
      my $count = $1;
      my $thing_type = $2;
      my $things = $3;
      push (@retval, @{transform_get_elements_from_list($input, $count, $thing_type, $things)})
   }
   #check for 'or'
   elsif ($input =~ m{\bor\b}i) {
      push (@retval, @{transform_or($input)});
   }
   #check for rolls
   elsif ($input =~ m{d\d}i) {   #matches digit, 'd', digit
      push (@retval, @{transform_rolls($input)});
   }
   #check for "roll pigs"
   elsif ($input =~ m{^\s*roll\s+pigs\s*$}i) {
      push (@retval, @{transform_roll_pigs()});
   }
   #lastly, check for a question mark at the end of the line
   elsif ($input =~ m{\?\s*$}i) {
      push (@retval, @{transform_yes_no($input)});
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
#              It makes sure the $input has $tag in it, followed, somewhere, by '://' or ',..'
#              it grabs everything after the last '://' (or ',..'), uri encodes it, and appends it
#              to $base_url
#
# Returns      a reference to a list of strings
##############################################################
sub transform_link {
   my $input = shift;
   my $tag = shift;
   my $base_url = shift;

   my @retval = ();

   if ($input =~ m{$tag.*$lr(.*)$}igx) {
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
   my $base_url = 'https://tvtropes.org/pmwiki/pmwiki.php/Main/';

   my @retval = ();

   if ($input =~ m{$tag.*$lr(.*)$}igx) {
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
# Usage        my $output_list_ref = transform_xkcd($input, $mobile_flag);
#
# Parameters   $input = the string that you wish to transform
#              $mobile_flag = an optional flag. If set to true, mobile links will
#                             be used instead of the standard ones.
#
# Description  Attempts to transform the input into a xkcd comic links
#
# Returns      a reference to a list of strings
##############################################################
sub transform_xkcd {
   my $input = shift;
   my $mobile_flag = shift;
   my $tag = 'xkcd';

   my @retval = ();

   if ($input =~ m{$tag.*$lr(.*)$}igx) {
      my $search = $1;
      #If it's only numbers, return the link to that numbered comic
      if ($search =~ /^\d+(?:\s+\d+)*$/) {
         my $base_url = $mobile_flag ? 'https://m.xkcd.com/' : 'https://xkcd.com/';
         #split it by numbers, and add a link to each
         foreach my $num (split(/\s+/, $search)) {
            push (@retval, $base_url.$num.'/');
         }
      }
      else {
         #return a link to the google search page for xkcd.
         my $action = 'https://www.google.com/cse';
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

   if ($input =~ m{bash.*$lr(.*)$}igx) {
      my $search = $1;
      $search =~ s/^\s+//;
      $search =~ s/\s+$//;
      my $base_url = 'http://www.bash.org/'; #As of September 11, 2018, https wasn't yet an option for this site.
      if ($search =~ m{^\d+$}) {
         push (@retval, $base_url.'?quote='.$search);
      }
      else {
         push (@retval, $base_url.'?sort=0&show=25&search='.$search);
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

   if ($input =~ m{(?:qdb|xkcdb).*$lr(.*)$}igx) {
      my $search = $1;
      $search =~ s/^\s+//;
      $search =~ s/\s+$//;
      my $base_url = 'http://xkcdb.com/'; #As of September 11, 2018, https wasn't yet an option for this site.
      if ($search =~ m{^\d+$}) {
         push (@retval, $base_url.$search);
      }
      else {
         push (@retval, $base_url.'?search='.$search);
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

my $SIDE_LEFT = "Side - Left";
my $SIDE_RIGHT = "Side - Right";
my $TROTTER = "Trotter";
my $RAZORBACK = "Razorback";
my $SNOUTER = "Snouter";
my $LEANING_JOWLER = "Leaning Jowler";

##############################################################
# Sub          transform_roll_pigs
# Usage        my $output_list_ref = transform_roll_pigs();
#
# Parameters   (none)
#
# Description  Rolls some pigs!
#
# Returns      a reference to a list of strings
##############################################################
sub transform_roll_pigs {

   my $retval = "";

   if (int(rand(500)) == 0) {
      $retval = "They're touching! You're back to zero points. Pass the pigs.";
   }
   else {
      my %score_table = (
         $SIDE_LEFT      => { $SIDE_LEFT =>  1, $SIDE_RIGHT =>  0, $TROTTER =>  5, $RAZORBACK =>  5, $SNOUTER => 10, $LEANING_JOWLER => 15 },
         $SIDE_RIGHT     => { $SIDE_LEFT =>  0, $SIDE_RIGHT =>  1, $TROTTER =>  5, $RAZORBACK =>  5, $SNOUTER => 10, $LEANING_JOWLER => 15 },
         $TROTTER        => { $SIDE_LEFT =>  5, $SIDE_RIGHT =>  5, $TROTTER => 20, $RAZORBACK => 10, $SNOUTER => 15, $LEANING_JOWLER => 20 },
         $RAZORBACK      => { $SIDE_LEFT =>  5, $SIDE_RIGHT =>  5, $TROTTER => 10, $RAZORBACK => 20, $SNOUTER => 15, $LEANING_JOWLER => 20 },
         $SNOUTER        => { $SIDE_LEFT => 10, $SIDE_RIGHT => 10, $TROTTER => 15, $RAZORBACK => 15, $SNOUTER => 40, $LEANING_JOWLER => 25 },
         $LEANING_JOWLER => { $SIDE_LEFT => 15, $SIDE_RIGHT => 15, $TROTTER => 20, $RAZORBACK => 20, $SNOUTER => 25, $LEANING_JOWLER => 60 },
      );

      my $pig1 = roll_pig();
      my $pig2 = roll_pig();

      my $points = $score_table{$pig1}->{$pig2};

      if ($points == 0) {
         $retval = 'Oinker.  No points for you this round.  Pass the pigs.';
      }
      else {
         my $position = $pig1 eq $pig2 ? $pig1 =~ m{Side} ? 'Sider.'
                                       : 'Double '.$pig1.'!'
                      : $pig1.' and '.$pig2.'.';

         $retval = 'You got a '.$position.' '.$points.' point'.($points == 1 ? '' : 's').'.';
      }
   }

   return [$retval];
}

##############################################################
# Sub          roll_pig
# Usage        my $result = roll_pig();
#
# Parameters   (none)
#
# Description  Rolls a single pig
#
# Returns      The position that it lands in
##############################################################
sub roll_pig {
   #Source: https://www.tandfonline.com/doi/full/10.1080/10691898.2006.11910593
   #Odds:  Side - Right (no dot) : 34.97  Threshold: 3497
   #      Side - Left (with dot) : 30.17             6514
   #                   Razorback : 22.37             8751
   #                     Trotter :  8.84             9635
   #                     Snouter :  3.04             9939
   #              Leaning Jowler :  0.61            10000
   my $rval = int(rand(10000));

   return $rval < 3497 ? $SIDE_RIGHT
        : $rval < 6514 ? $SIDE_LEFT
        : $rval < 8751 ? $RAZORBACK
        : $rval < 9635 ? $TROTTER
        : $rval < 9939 ? $SNOUTER
        : $rval < 10000 ? $LEANING_JOWLER
        : "Invalid"
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

   my @positive_answers = ('Yes', 'Probably', 'Sure', 'Definitely');
   my @negative_answers = ('No',  'Absolutely not!', 'Nope');
   my @neutral_answers = ('Maybe', 'Possibly', 'Sort of');
   my @silly_answers = (
      'Rub your belly three times and ask again.',
      'Light some candles and ask again.',
      '42',
   );

   my @possibilities = (
      (@positive_answers) x 10,
      (@negative_answers) x 10,
      (@neutral_answers) x 3,
      (@silly_answers) x 1,
   );

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

##############################################################
# Sub          transform_get_elements_from_list
# Usage        my $output_list_ref = transform_get_elements_from_list($input, $count, $thing_type, $things);
#
# Parameters   $input = the string that you wish to transform
#              $count = the number of things desired.
#              $thing_type = the type of things we're getting
#              $things = the list of things, or a description of them.
#
# Description  Attempts to transform the input, getting a number of random elements from a list.
#
# Returns      a reference to a list of strings
##############################################################
sub transform_get_elements_from_list {
   my $input = shift;
   my $count = shift;
   my $thing_type = shift;
   my $things = shift;

   my @lucky_picks = ();
   my $sorter = undef;
   my $tried_real_hard = 0;

   if ($thing_type =~ m{numbers?}i) {
      push(@lucky_picks, @{get_random_elements_from($count, get_possible_numbers($things))});
      $sorter = sub { $a <=> $b };
      $tried_real_hard = 1;
   }
   else {
      push(@lucky_picks, @{get_random_elements_from($count, get_possibilities($things))});
      $tried_real_hard = 1;
   }

   my $retval = 'Unknown type of things. I can only do numbers right now.';

   if ($tried_real_hard) {
      my $pick_count = scalar(@lucky_picks);
      if ($pick_count == 0) {
         $retval = 'No elements could be selected.';
      }
      elsif ($pick_count == 1) {
         $retval = '' . $lucky_picks[0];
      }
      else {
         # default the sorter to case insensitive.
         if (! defined $sorter) {
            $sorter = sub { lc($a) cmp lc($b) };
         }
         my @ordered_picks = sort($sorter @lucky_picks);
         $retval = join(', ', @ordered_picks[0..$#ordered_picks-1]) . ' and ' . $ordered_picks[-1];
      }
   }

   return [$retval];
}

##############################################################
# Sub          get_possible_numbers
# Usage        my $output_list_ref = get_possible_numbers($description);
#
# Parameters   $description = a description string of the numbers desired.
#                 Example formats: "1 to 3" "8-55" "2:7" "up to 42" "1, 2, 3, 8 .. 19"
#
# Description  Converts the provided description into a list of the numbers as described.
#
# Returns      a reference to a list of numbers.
##############################################################
sub get_possible_numbers {
   my $description = shift;

   my @retval = ();

   # Look for "up to <number>" entries.
   # Note: This is just shorthand for "1 to <number>" so we don't need to worry about the number being negative.
   if ($description =~ m{^up\s+to\s+(\d+)$}i) {
      my $stop = $1;
      if ($stop >= 1) {
         push(@retval, 1 .. $stop);
      }
   }
   # Okay, check for <number> [ [<delimiter] <number> ...]
   # Examples:
   #     "-1, -2, -3"
   #     "1 to 100"
   #     "3:99, 105,110-115 -10-10"
   elsif ($description =~ m{^(?:-?\d+)(?:\s*(?:,|-|to|:|\.\.|\s)?\s*(?:-?\d+))*$}) {
      $description =~ s{\s*,\s*}{,}g;                   # Get rid of spaces around commas
      $description =~ s{\s*(?:to|:|\.\.)\s*}{:}g;       # Get rid of spaces around span delimiters (except -), and turn them all into :
      $description =~ s{\s*-\s*}{-}g;                   # Get rid of spaces around -.
      $description =~ s{(\d)-}{$1:}g;                   # If a digit is followed by a -, change the - to a :
      $description =~ s{\s+}{,}g;                       # Turn all one-or-more spaces into a comma
      # Split on the commas because they now represent each separate entry to look at
      foreach my $entry (split(',', $description)) {
         # If the entry is a range, add the whole range to the return value
         if ($entry =~ m{^(-?\d+):(-?\d+)$}) {
            push(@retval, @{get_number_range($1, $2)});
         }
         # If the entry is just a number, just add it.
         elsif ($entry =~ m{^(-?\d+)$}) {
            push(@retval, $1);
         }
      }
   }

   return unique(\@retval);
}

##############################################################
# Sub          get_number_range
# Usage        my $range = get_number_range($v1, $v2);
#
# Parameters   $v1 = one of the values to either start or stop at.
#              $v2 = the other value to either start or stop at.
#
# Description  Gets all the numbers between, and including $v1 and $v2.
#
# Returns      A reference to a list of numbers.
##############################################################
sub get_number_range {
   my $v1 = shift;
   my $v2 = shift;
   return $v1 < $v2 ? [$v1 .. $v2] : [$v2 .. $v1];
}

##############################################################
# Sub          get_possibilities
# Usage        my $output_list_ref = get_possibilities($things);
#
# Parameters   $things = a string with a bunch of things in it.
#                    Can be semi-colon delimited, comma delimited or space delimited.
#                    Delimiters looked for in that order.
#
# Description  Separates out the string of $things into a list of things.
#
# Returns      a reference to a list of things.
##############################################################
sub get_possibilities {
   my $things = shift;

   my @retval = $things =~ m{;} ? split(m{\s*;\s*}, $things)
              : $things =~ m{,} ? split(m{\s*,\s*}, $things)
              :                   split(m{\s+}, $things);

   return \@retval;
}

##############################################################
# Sub          get_random_elements_from
# Usage        my $output_list_ref = get_random_elements_from($count, \@things);
#
# Parameters   $count = the number of things desired.
#              @things = the list of things.
#
# Description  Gets $count random entries from @things (without duplicates).
#              If $count is greater than the number of elements in @things, all of @things is returned.
#              If $count is 0 or negative, an empty list is returned.
#
# Returns      a reference to a list
##############################################################
sub get_random_elements_from {
   my $count = shift;
   my $things = shift;

   my $things_length = scalar(@$things);

   my @retval = ();

   if ($count == $things_length) {
      push(@retval, @$things);
   }
   elsif ($count == 1 && $things_length > 1) {
      push(@retval, $things->[int(rand($things_length))]);
   }
   elsif ($count > 1 && $count < $things_length) {
      my @unsorted = shuffle(@$things);
      push(@retval, @unsorted[0..($count-1)]);
   }

   return \@retval;
}

##############################################################
# Sub          unique
# Usage        my $output_list_ref = unique(\@list);
#
# Parameters   @list = the list of things to make unique.
#
# Description  Gets a list of items without duplicates.
#              Order of the original list is maintained, except only the first instance
#              of an entry will be in the returned list ref.
#
# Returns      a reference to a list
##############################################################
sub unique {
   my $input = shift;
   my %seen;
   my @retval;
   for my $entry (@$input) {
      if (!$seen{$entry}) {
         $seen{$entry} = 1;
         push (@retval, $entry);
      }
   }
   return \@retval;
}

1;
