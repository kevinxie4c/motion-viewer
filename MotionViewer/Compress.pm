package MotionViewer::Compress;

use File::Spec;
use File::Path qw(remove_tree);
use Carp;
use Exporter 'import';
use strict;
use warnings;

our %EXPORT_TAGS = ( 'all' => [qw(compress decompress)]);
our @EXPORT_OK = @{$EXPORT_TAGS{'all'}};

my $sample_file_name = 'samples.dat';
# Format:
# [
#     [
#         number of samples (I32)
#         [
#             length of pose vector (I32)
#             pose vector (double vector)
#             length of ref vector (I32)
#             ref vector (double vector)
#             cost (double)
#         ],
#         ... (order by ascending cost)
#     ],
#     ...
# ]
sub compress {
    my $dir = shift;
    my $itr_pat = File::Spec->catdir($dir, '*');
    my @samples;
    for my $itr_dir(glob $itr_pat) {
        next unless $itr_dir =~ /(\d+)$/ && -d $itr_dir;
        my $i = $1;
        my $file_pat = File::Spec->catfile($itr_dir, '*');
        my @list;
        for my $file(glob $file_pat) {
            next unless -f $file;
            open my $fh_in, '<', $file;
            my $it = {};
            $_ = <$fh_in>;
            $it->{pos} = [split];
            $_ = <$fh_in>;
            $it->{ref} = [split];
            $_ = <$fh_in>;
            $it->{cost} = $_;
            push @list, $it;
            close $fh_in;
        }
        remove_tree($itr_dir);
        $samples[$i] = [sort { $a->{cost} <=> $b->{cost} } @list];
    }
    open my $fh_out, '>:raw', File::Spec->catfile($dir, $sample_file_name);
    for my $list(@samples) {
        next unless defined $list;
        print $fh_out pack('L', scalar(@$list));
        for (@$list) {
            my @pos = @{$_->{pos}};
            my @ref = @{$_->{ref}};
            my $cost = $_->{cost};
            print $fh_out pack('L', scalar(@pos));
            print $fh_out pack('d*', @pos);
            print $fh_out pack('L', scalar(@ref));
            print $fh_out pack('d*', @ref);
            print $fh_out pack('d', $cost);
        }
    }
    close $fh_out;
}

my $size_int = length(pack('L', 0));
my $size_float = length(pack('d', 0)); # size of floating point number (not type float!)
sub decompress {
    my $dir = shift;
    my $samples = [];
    my $file = File::Spec->catfile($dir, $sample_file_name);
    open my $fh_in, '<:raw :bytes' , $file or croak "cannot open $file: $!";
    my $num;
    my $i = 0;
    while (read($fh_in, $num, $size_int)) {
        $num = unpack 'L', $num;
        for (1 .. $num) {
            my ($length, $buf, $cost);
            
            read($fh_in, $length, $size_int);
            $length = unpack 'L', $length;
            read($fh_in, $buf, $length * $size_float);
            my @pos = unpack "d$length", $buf;

            read($fh_in, $length, $size_int);
            $length = unpack 'L', $length;
            read($fh_in, $buf, $length * $size_float);
            my @ref = unpack "d$length", $buf;

            read($fh_in, $cost, $size_float);
            $cost = unpack 'd', $cost;
            push @{$samples->[$i]}, { pos => \@pos, ref => \@ref, cost => $cost };
        }
        ++$i;
    }
    close $fh_in;
    $samples;
}

1;
