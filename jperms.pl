#!/usr/bin/perl
#
# Author: John Buxton, 2016

use strict;
use warnings;

use File::Find;

# 1. all patterns will automatically be surrounded by ^ and $
# 2. for each file or directory found, patterns are processed from top to bottom
#    until the first match is found
# 3. a pattern may match both files and directories, but dir
#    perms are only applied to directories, and file perms are only applied
#    to files
# 4. specify '-' for any or all of owner, group or perms if those
#    attributes are to be un-altered when a match is found

my $patterns_config = '
  # pattern                          owner   group  dir_perms file_perms
  #
  \./appdir/data.*/proj/cards	     appuser grp2    770      -
  \./appdir/data.*/proj/r/r_import   appuser grp2    770      -
  \./appdir/data.*/proj/outbound 	 appuser grp2   2770      -
  \./appdir/data.*/proj/.*/inbox 	 appuser grp2    770      -
  \./appdir/data.*/proj/[^/]+        appuser grp2    750      -
  \./appdir/data[^/]*/proj	         appuser grp2    750      -
  \./appdir/data.*/tws/logs 	     appuser grp2    770      -
  \./appdir/data.*/tws 	             appuser grp2    750      -
  \./appdir/data.*/logs 	         appuser grp2    770      -
  \./appdir/data.*/scripts 	         appuser grp2    750      -
  \./appdir/data.*                   appuser grp2    770      660
  \./appdir/.*                       -       -  	 -        -
  \./appdir	                         appuser appgrp  775      -
';

my %pattern_details = ();
my @pattern_list = ();

for my $line (split("\n", $patterns_config)) {
  my @fields = split(' ', $line);
  my ($pattern, $owner, $group, $dperm, $fperm) = split(' ', $line);
  next if (!defined $pattern || $pattern =~ /^ *#/);
  push @pattern_list, $pattern;
  my %pattern_attributes;
  $owner = '' if $owner eq '-';
  $group = '' if $group eq '-';
  @pattern_attributes{qw/owner group dperm fperm/}
    = ($owner, $group, $dperm, $fperm);
  $pattern_details{$pattern} = \%pattern_attributes;
}

for my $top (@ARGV) {
  find(sub {
    my $relname = $_;   # full name relative to top dir

    for my $pattern (@pattern_list) {
      if ($File::Find::name =~ /^${pattern}$/) {

        print "$File::Find::name matches pattern $pattern\n";

        my $pa = $pattern_details{$pattern};
        my $new_owner = $pa->{owner} . ':' . $pa->{group};
        print "  chown $new_owner $relname\n" if ($new_owner ne ':');

        if ($pa->{dperm} ne '-' && -d $relname) {
          print 'DIR   chmod ' . $pa->{dperm} . " $relname\n";
        }

        if ($pa->{fperm} ne '-' && -f $relname) {
          print 'FILE  chmod ' . $pa->{fperm} . " $relname\n";
        }

        return;
      }
    }
  }, $top);
}
