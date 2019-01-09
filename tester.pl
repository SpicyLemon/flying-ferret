#!/usr/bin/perl
use strict;
use warnings;
use lib qw(.);
use flyingferret;

my $input = "should I buy a new car?";

if ($ARGV[0]) {
   $input = join(' ', @ARGV);
}

my @output = @{flyingferret::transform($input)};

print "'$input' transforms into this:\n";
print join("\n", @output)."\n";