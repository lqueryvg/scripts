#!/usr/bin/perl
#
# Author: John Buxton, 2016

use strict;
use warnings;
use File::Find;
use Getopt::Long;
use Pod::Usage;
use IO::File;
use POSIX;
use File::stat;

# Get command line options
#
my %options;
GetOptions(\%options, 'help|?|h', 'file=s',
                      'man', 'verbose', 'dir=s', 'no_run');
pod2usage(1) if $options{help};
pod2usage(-verbose => 2) if $options{man};
pod2usage({ -message => q{ERROR: -file is required} }) unless $options{file};
pod2usage({ -message => q{ERROR: -dir is required} })  unless $options{dir};

# Subroutines

sub zero_pad_octal_string {
  my ($str) = @_;
  if ($str ne '-' && substr($str, 0, 1) ne '0') {
    $str = '0' . $str;
  }
  #return oct($str);
  return $str;
}

# Process pattern rules

my $fh = IO::File->new($options{file}, q{<})
  or die "ERROR: unable to open patterns file $options{file}\n";


print "parsing pattern rules...\n" if $options{verbose};

my %pattern_details = ();
my @pattern_list = ();


while (my $line = <$fh>) {

#for my $line (split("\n", $patterns_config)) {

  print "pattern line = $line\n" if $options{verbose};

  my ($pattern, $owner, $group, $dperm, $fperm) = split(' ', $line);
  next if (!defined $pattern || $pattern =~ /^ *#/);  # skip comments

  push @pattern_list, $pattern;

  my %pattern_attributes;
  $owner = '' if $owner eq '-';
  $group = '' if $group eq '-';
  $dperm = zero_pad_octal_string($dperm);
  $fperm = zero_pad_octal_string($fperm);
  @pattern_attributes{qw/owner group dperm fperm/}
    = ($owner, $group, $dperm, $fperm);

  $pattern_details{$pattern} = \%pattern_attributes;
}

sub get_id {
  # Safely convert user or group name to a numerical id suitable
  # for use with chown. -1 is returned if user or group not found,
  # which will tell chown to leaving user or group un-altered.
  my ($name, $sub) = @_;
  my $id = $sub->($name);
  return $id if (defined $id);
  return -1;
}

#sub zero_pad_octal_string {
#  # safely convert octal string mode to numeric for use with chmod
#  my ($str) = @_;
#  if (substr($str, 0, 1) ne '0') {
#    $str = '0' . $str;
#  }
#  return oct($str);
#}

print "starting descent at $options{dir}\n" if $options{verbose};

find({no_chdir => 1, wanted => sub {
  #print '$File::Find::dir  = ' . $File::Find::dir  . "\n";
  #print '$_                = ' . $_                . "\n";
  #print '$File::Find::name = ' . $File::Find::name . "\n";

  my $f = $File::Find::name;   # the current path, relative to top dir
                            # and including filename

  print "$f\n" if $options{verbose};

  for my $pattern (@pattern_list) {
    if ($f =~ /^${pattern}$/) {

      print "$f matches pattern $pattern\n" if $options{verbose};

      my $pa = $pattern_details{$pattern};
      #use Data::Dumper;
      #print Dumper $pa;

      my $sb = stat($f);

      if ($options{no_run}) {
        # TODO - improve output
        my $new_owner = $pa->{owner} . ':' . $pa->{group};
        print "chown $new_owner $f\n" if ($new_owner ne ':');
        my $uid = get_id($pa->{owner}, \&POSIX::getpwnam);
        my $gid = get_id($pa->{group}, \&POSIX::getgrnam);

        print "chown $uid, $gid, $f\n";
      } else {
        # TODO - really run it
        #chown $uid, $gid, $f;
        # TODO - check status
      }

      #printf "mode is " . ($sb->mode & 07777) . "\n";

      my $current_mode = sprintf('%04o', $sb->mode & 07777);
      printf "current mode is $current_mode\n" if $options{verbose};
      #my $fperm = oct_str_to_perm($pa->{fperm});
      #my $dperm = oct_str_to_perm($pa->{dperm});
      my $fperm = $pa->{fperm};
      my $dperm = $pa->{dperm};

      # if dperm specified and is a dir
      if ($pa->{dperm} ne '-' && -d $f) {
        print "target DIR mode is $dperm\n";

        # if new perm is different
        if ($current_mode != $dperm) {
          print "chmod $dperm (" . $pa->{dperm} . "), $f # DIR\n";
          if ($options{no_run}) {
            # TODO - uncomment
            print 'run: chmod ' . oct_str_to_perm($pa->{dperm}) . ", $f\n";
            # TODO - check status
          }
        } else {
          print "no changed needed\n" if $options{verbose};
        }
      }

      # if fperm specified and is a file
      if ($pa->{fperm} ne '-' && -f $f) {
        print "target FILE mode is $fperm\n";
        if ($current_mode != $fperm) {
          print "chmod $fperm (" . $pa->{fperm} . "), $f # FILE\n";
          if ($options{no_run}) {
            # TODO - uncomment
            print 'run: chmod ' . oct_str_to_perm($pa->{fperm}) . ", $f\n";
            # TODO - check status
          }
        } else {
          #chmod oct_str_to_perm($pa->{fperm}), $f;
          print "no changed needed\n" if $options{verbose};
        }
      }

      return;
    }
  }
}}, $options{dir});

__END__

=head1 jperms.pl

recursively set permissions and ownerships according to pattern rules

=head1 OPTIONS

jperms.pl [options] [dir ...]

 Options:
   -help|-h|-?     help
   -man            full documentation
   -dir            directory to descend
   -file           patterns file
   -verbose        extra debug
   -no_run         don't run any commands

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

- file paths include the top level path specified on the command line.

- The path of each file or directory found during the descent is compared
against each pattern in turn (top to bottom) until a match is found.  Pattern
matching for that path then stops and the owner, group, dir_perms
& file_perms associated with the matching pattern are applied to the file or
directory, where appropriate (see below).

- A value of '-' for any or all of owner, group, dir_perms or file_perms
means that this attribute are to be un-altered when a match is found.

- file or dir perms must be specified in octal

- A pattern may match both files and directories, but dir_perms are only ever
applied to directories, and file_perms are only applied to files

=head1 COMMENTS

Lines starting with a '#' (optionally preceeded by whitespace)
are treated as comments and ignored.

=head1 EXAMPLE

Example pattern file:

# pattern                      owner   group  dperm  fperm

\./test/data.*/proj/cards      appuser grp2    770   -
\./test/data.*/proj/r/r_import appuser grp2    770   -
\./test/data.*/proj/outbound   appuser adm    2770   -
\./test/data.*/proj/.*/inbox   appuser grp2    770   -
\./test/data.*/proj/[^/]+      appuser grp2    750   -
\./test/data[^/]*/proj         appuser adm     750   -
\./test/data.*/tws/logs        appuser grp2    770   -
\./test/data.*/tws             appuser grp2    750   -
\./test/data.*/logs            appuser grp2    770   -
\./test/data.*/scripts         root    adm     750   -
\./test/data.*                 appuser grp2    770   660
\./test/.*                     -       -       -     -
\./test                        appuser appgrp  775   -
