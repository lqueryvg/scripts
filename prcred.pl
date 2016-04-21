#!/usr/bin/perl
#
# prcred.pl - print credentials of a running process
# 
# Copyright 2012 John Buxton, HCT Solutions Ltd
#
# Version 1.0 - 28/11/12
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

die "Sorry, AIX only\n" if ($^O ne 'aix');

my $proc_id = shift @ARGV;
if (!defined($proc_id)) {
  die "usage: proccred.pl {pid}\n";
}

# Unpack whole cred file into list of 32 bit unsigned ints.

my $cred_file = "/proc/$proc_id/cred";
open(my $fh, '<', $cred_file) or die "unable to open $cred_file: $!\n";
local $/;	# enable localized slurp mode
my @uint32 = unpack("(L1)*", <$fh>);
close($fh);

sub to_64 {	# convert two 32 bit ints to 64 bit
  my ($high, $low) = @_;
  return(($high * 2**32) + $low);
}

sub unpack32 {
  return shift @uint32;
}

sub unpack64 {
  if (!defined wantarray) {
    # called in void context, so avoid calc
    # and just skip...
    unpack32(); unpack32();
    return;
  }
  return to_64(unpack32(), unpack32());
}

# unpack as per prcred struct in sys/procfs.h

my %prcred = map { $_ => unpack64() } qw/
  pr_euid pr_ruid pr_suid
  pr_egid pr_rgid pr_sgid
/;

# skip padding
foreach (1..8) {
  unpack64();
}
unpack32();

my $pr_ngroups = unpack32();
my @supplimentary_group_ids;
while ($pr_ngroups > 0) {
  push @supplimentary_group_ids, unpack64();
  $pr_ngroups--;
}

sub out_string {
  my ($varname, $id, $name) = @_;
  return "$varname=$id($name)";
}

for my $var (qw/pr_euid pr_ruid pr_suid/) {
  my $id = $prcred{$var};
  print out_string($var, $id, getpwuid($id)) . "\n";
}

for my $var (qw/pr_egid pr_rgid pr_sgid/) {
  my $id = $prcred{$var};
  print out_string($var, $id, getgrgid($id)) . "\n";
}

print 'pr_groups=' . join(',',
  map {
    $_ . '(' . getgrgid($_) . ')'
  } @supplimentary_group_ids
) . "\n";
exit;

__END__;
