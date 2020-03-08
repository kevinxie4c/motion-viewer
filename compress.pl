#!/usr/bin/env perl
use File::Spec;
use Parallel::ForkManager;
use FindBin qw($Bin);
use lib $Bin;
use MotionViewer::Compress qw(:all);
use strict;
use warnings;

my $pm = Parallel::ForkManager->new(8);
#for my $sample_dir(qw(samples_m samples_o)) {
for my $sample_dir(qw(samples)) {
    my $pat = File::Spec->catdir($sample_dir, '*', '*');
    DIR:
    for my $dir (glob $pat) {
        $pm->start and next DIR;

        my (undef, $round_dir, $trial_dir) = File::Spec->splitdir($dir);
        next unless $round_dir =~ /^\d+$/ && $trial_dir =~ /^\d+$/;
        print "compressing $dir\n";
        compress($dir);

        $pm->finish;
    }
}
$pm->wait_all_children;
