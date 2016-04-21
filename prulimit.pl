#!/usr/bin/perl
#
# prulimit.pl - print ulimits of a running process
# 
# Copyright 2012 John Buxton, HCT Solutions Ltd
#
# Version 1.1 - 06/02/13
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
use Math::BigInt;

die "Sorry, AIX only\n" if ($^O ne 'aix');

my $SPACE = q{ };

my $pid = shift @ARGV;
if (!defined($pid)) {
  die "usage: prulimit.pl {pid}\n";
}

# Convert pid to hex, then find process slot number from pstat.

my $hexpid = sprintf('%x', $pid);
#print "search for $hexpid\n";

my $command = 'pstat -A';
my $slot;
my $regexp = qr{
  # example input lines for this regexp:
  # SLT ST    TID      PID    CPUID  POLICY PRI CPU    EVENT  PROCNAME     FLAGS
  #   0 s       3        0  unbound    FIFO  10  78            swapper
  ^		# start of line
  \s*	# optional whitespace
  (\d+)	# capture slot number
  \s+	# space
  [^z]  # ST
  \s+	# space
  \w+	# TID
  \s+	# space
  $hexpid	# the hex PID we are looking for
  \s+	# space
  .*$	# rest of line
}x;

open(my $fh, '-|', $command) or die "unable to run command $command: $!\n";
while (my $line = <$fh> ) {
  chomp $line;
  if ($line =~ /$regexp/) {
    $slot = $1;
    last;	# there may be more slots for this process (multiple threads)
		# but we don't want them -> they will all have the same ulimits
  }
} 
close($fh);
if (!defined $slot)  {
  die "unable to get process slot number for process $pid (hex = 0x$hexpid)\n";
}

# use kdb with the process slot number to find rlimits

$regexp = qr{
  # example kdb line for this regexp:
  #   rlimit_flag[CPU]...... cur INF max INF

  \s+	# spaces
  (\w+) # array name (e.g. rlimit_flag, rlimit, saved_rlimit)
  \[	# open square bracket
  (\w+) # resource name, eg. CPU, FSIZE, RSS, etc
  \]	# close square bracket
  \.+	# literal dots
  \s	# space
  cur   # literal "cur"
  \s    # space
  (\w+) # soft limit value
  \s    # space
  max   # literal "max"
  \s    # space
  (\w+) # hard limit value
}x;

my %limits;
$command = "echo 'user $slot' | kdb";
open($fh, '-|', $command) or die "unable to run command $command: $!\n";
while (my $line = <$fh> ) {
  if ($line =~ /$regexp/) {
    chomp $line;
    my ($array_name, $kdb_resource) = ($1, $2);
    $limits{$array_name}{$kdb_resource}{soft_limit} = $3;
    $limits{$array_name}{$kdb_resource}{hard_limit} = $4;
  }
}
#use Data::Dumper;
#print Dumper \%limits;

my @config_names = (
  "time(seconds)       ", "CPU",       1,
  "file(blocks)        ", "FSIZE",     1,
  "data(kbytes)        ", "DATA",      1024,
  "stack(kbytes)       ", "STACK",     1024,
  "memory(kbytes)      ", "RSS",       1024,
  "coredump(blocks)    ", "CORE",      1,
  "nofiles(descriptors)", "NOFILE",    1,
  "threads(per process)", "THREADS",   1,
  "processes(per user) ", "NPROC",     1
);
my @output_names;

sub remove_chunk {
  my ($str_ref, $len) = @_;
  return substr($$str_ref, 0, $len, q{});
}

sub from_hex {
  my ($str) = @_;

  # would have preferred to use Math::BigInt->from_hex
  # but not ubiquitous on AIX

  my $total = 0;
  my $chunk_len = 4;

  while ((my $chunk_str = remove_chunk(\$str, $chunk_len)) ne q{}) {
    $total *= 2 ** ($chunk_len * 4);
    $total += hex($chunk_str);
  }
  return $total;
}

print "# name,soft,hard\n";
while(scalar(@config_names) > 0) {

  my $output_name  = shift @config_names;
  my $kdb_resource = shift @config_names;
  my $divisor      = shift @config_names;

  # choose correct values to use based on flag:
  #     *   RLFLAG_SML => limit correctly represented in 32-bit U_rlimit
  #     *   RLFLAG_INF => limit is infinite
  #     *   RLFLAG_MAX => limit is in 64_bit U_saved_rlimit.rlim_max
  #     *   RLFLAG_CUR => limit is in 64_bit U_saved_rlimit.rlim_cur

  print $output_name;
  for my $type (qw/soft hard/) {
    my $value_str;
    my $flag = $limits{rlimit_flag}{$kdb_resource}{"${type}_limit"};
    my $array_name;
    if ($flag eq 'MAX' || $flag eq 'CUR') {
      $array_name = 'saved_rlimit';
    } elsif ($flag eq 'INF') {
      $value_str = 'unlimited';
    } else {
      $array_name = 'rlimit';
    }


    if (!defined $value_str) {
      $value_str = $limits{$array_name}{$kdb_resource}{"${type}_limit"};
      $value_str = from_hex($value_str);
    }
    print ",$value_str";
  }
  
  print "\n";
}

exit;

__END__;
