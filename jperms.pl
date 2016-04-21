#!/usr/bin/perl
#
# Author: John Buxton, 2016

use strict;
use warnings;

use File::Find;

my $patterns_config = '
  # pattern                      owner   group  dperm    fperm
  #
  \./test/data.*/proj/cards	     appuser grp2    770      -
  \./test/data.*/proj/r/r_import appuser grp2    770      -
  \./test/data.*/proj/outbound 	 appuser adm    2770      -
  \./test/data.*/proj/.*/inbox 	 appuser grp2    770      -
  \./test/data.*/proj/[^/]+      appuser grp2    750      -
  \./test/data[^/]*/proj	     appuser adm     750      -
  \./test/data.*/tws/logs 	     appuser grp2    770      -
  \./test/data.*/tws 	         appuser grp2    750      -
  \./test/data.*/logs 	         appuser grp2    770      -
  \./test/data.*/scripts 	     root    adm     750      -
  \./test/data.*                 appuser grp2    770      660
  \./test/.*                     -       -  	 -        -
  \./test	                     appuser appgrp  775      -
';

use Getopt::Long;
use Pod::Usage;
my $verbose = '';
my $help = '';
my $man = '';
my $dir = '';
my $no_run = '1'; # TODO

GetOptions('help|?|h' => \$help,
           'man'      => \$man,
           'verbose'    => \$verbose,
           'dir=s'    => \$dir,
           'no_run'    => \$no_run,
);

pod2usage(1) if $help;
pod2usage(-exitval => 1, -verbose => 2) if $man;

print "parsing pattern rules...\n" if $verbose;

my %pattern_details = ();
my @pattern_list = ();

for my $line (split("\n", $patterns_config)) {

  print "pattern line = $line\n" if $verbose;

  my ($pattern, $owner, $group, $dperm, $fperm) = split(' ', $line);
  next if (!defined $pattern || $pattern =~ /^ *#/);  # skip comments

  push @pattern_list, $pattern;

  my %pattern_attributes;
  $owner = '' if $owner eq '-';
  $group = '' if $group eq '-';
  @pattern_attributes{qw/owner group dperm fperm/}
    = ($owner, $group, $dperm, $fperm);

  $pattern_details{$pattern} = \%pattern_attributes;
}

sub get_id {
  my ($name, $sub) = @_;
  my $id = $sub->($name);
  return $id if (defined $id);
  return -1;
}

sub oct_str_to_perm {
  # safely convert string to octal
  my ($str) = @_;
  if (substr($str, 0, 1) ne '0') {
    $str = '0' . $str;
  }
  return oct($str);
}

print "starting descent at $dir\n" if $verbose;
find({no_chdir => 1, wanted => sub {
  #print '$File::Find::dir  = ' . $File::Find::dir  . "\n";
  #print '$_                = ' . $_                . "\n";
  #print '$File::Find::name = ' . $File::Find::name . "\n";

  my $f = $File::Find::name;   # the current path, relative to top dir
                            # and including filename

  print "$f\n" if $verbose;

  for my $pattern (@pattern_list) {
    if ($f =~ /^${pattern}$/) {

      print "$f matches pattern $pattern\n" if $verbose;

      my $pa = $pattern_details{$pattern};
      #use Data::Dumper;
      #print Dumper $pa;


      if ($no_run) {
        # TODO - improve output
        my $new_owner = $pa->{owner} . ':' . $pa->{group};
        print "chown $new_owner $f\n" if ($new_owner ne ':');
        my $uid = get_id($pa->{owner}, \&CORE::getpwnam);
        my $gid = get_id($pa->{group}, \&CORE::getgrnam);
        print "chown $uid, $gid, $f\n";
      } else {
        # TODO - really run it
      }

      #print $pa->{dperm} . "\n";
      #print "$f\n";
      #use Cwd;
      #print 'cwd = ' . getcwd() . "\n";
      #print "dir\n" if (-d "$f");
      if ($pa->{dperm} ne '-' && -d $f) {
        if ($no_run) {
          print 'chmod ' . oct_str_to_perm($pa->{dperm}) .
                '(' . $pa->{dperm} . "), $f # DIR\n";
        } else {
          # TODO - uncomment
          #chmod oct_str_to_perm($pa->{dperm}), $f;
        }
      }

      if ($pa->{fperm} ne '-' && -f $f) {
        if ($no_run) {
          print 'chmod ' . oct_str_to_perm($pa->{fperm}) .
                '(' . $pa->{fperm} . "), $f # FILE\n";
        } else {
          # TODO - uncomment
          #chmod oct_str_to_perm($pa->{fperm}), $f;
        }
      }

      return;
    }
  }
}}, $dir);

__END__

=head1 jperms.pl

recursively set permissions and ownerships according to pattern rules

=head1 SYNOPSIS

jperms.pl [options] [dir ...]

 Options:
   -help|-h|-?    help
   -man           full documentation
   -dir           directory to descend
   -verbose       extra debug
   -no_run        don't run any commands

=head1 DESCRIPTION

jperms.pl descends the specified directory tree applying permissions and
ownerships to each file or directory found according to a set
of pattern rules.

=head1 RULES

Pattern rules are specified as a list of lines.


Each line consists of 5 fields separated by whitespace:

  pattern   owner   group   dir_perms   file_perms

- pattern is a regex (NOT a fileglob!) to be matched against each path
found during the tree descent.

- Patterns are automatically surrounded by ^ and $ when matching, meaning
that it must match the whole of the current path (not just part of it).

- File paths include the top level path specified on the command line.

- The path of each file or directory found during the descent is compared
against each pattern in turn (top to bottom) until a match is found.  Pattern
matching for that path then stops and the owner, group, dir_perms
& file_perms associated with the matching pattern are applied to the file or
directory, where appropriate (see below).

- A value of '-' for any or all of owner, group, dir_perms or file_perms
means that this attribute are to be un-altered when a match is found.

- A pattern may match both files and directories, but dir_perms are only ever
applied to directories, and file_perms are only applied to files

=head1 COMMENTS

Lines starting with a '#' (optionally preceeded by whitespace)
are treated as comments and ignored.
