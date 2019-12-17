#!/usr/bin/env perl
use File::Spec;
use FindBin qw($Bin);
use lib $Bin;
use MotionViewer::Compress qw(:all);
use strict;
use warnings;

for my $sample_dir(qw(samples_m samples_o)) {
    my $pat = File::Spec->catdir($sample_dir, '*', '*');
    for my $dir (glob $pat) {
        my (undef, $round_dir, $trial_dir) = File::Spec->splitdir($dir);
        next unless $round_dir =~ /^\d+$/ && $trial_dir =~ /^\d+$/;
        compress($dir);
    }
}
