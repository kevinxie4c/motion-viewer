package MotionViewer::BVH;

use parent 'Mocap::BVH';
use Math::Trig;
use OpenGL::Modern qw(:all);
use GLM;
use Carp;
use strict;
use warnings;

sub load {
    my $class = shift;
    my $this = $class->SUPER::load(shift);

    $this->load_geometry_config(shift) if @_;
    
    for my $joint($this->joints) {
        my @vertices;

        # lines
        #for ($joint->children) {
        #    push @vertices, (0, 0, 0, $_->offset);
        #}
        #if ($joint->end_site) {
        #    push @vertices, (0, 0, 0, $joint->end_site);
        #}

        # cube
        if (exists $this->{geometry_config}{$joint->name}) {
            @vertices = @{$this->{geometry_config}{$joint->name}};
        } else {
            for ($joint->children) {
                push @vertices, &create_cube($_->offset);
            }
            if ($joint->end_site) {
                push @vertices, &create_cube($joint->end_site);
            }
        }
        #print "@vertices\n";
        
        if (@vertices) {
            # lines
            #$this->{buffer}{$joint->name} = MotionViewer::Buffer->new(1, @vertices);
            #$this->{count}{$joint->name} = @vertices / 3;

            #cube
            $this->{buffer}{$joint->name} = MotionViewer::Buffer->new(2, @vertices);
            $this->{count}{$joint->name} = @vertices / 6;
        }
    }

    $this;
}

sub shader {
    my $this = shift;
    $this->{shader} = shift if @_;
    $this->{shader};
}

sub set_position {
    my $this = shift;
    for ($this->joints) {
        $_->{position} = [splice(@_, 0, scalar($_->channels))];
    }
}

my $identity_mat = GLM::Mat4->new(
    1, 0, 0, 0, 
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
);
    
sub draw {
    my $this = shift;
    my $model_matrix = GLM::Mat4->new($identity_mat);
    $this->draw_joint($this->root, $model_matrix);
}

my %axis = (
    X => GLM::Vec3->new(1, 0, 0),
    Y => GLM::Vec3->new(0, 1, 0),
    Z => GLM::Vec3->new(0, 0, 1),
);

sub draw_joint {
    my ($this, $joint, $model_matrix) = @_;
    my @channels = $joint->channels;
    my @positions = @{$joint->{position}};
    my $offset = GLM::Vec3->new($joint->offset);
    $model_matrix = GLM::Functions::translate($model_matrix, $offset);
    if (@channels == 6) {
        if ($channels[0] eq 'Xposition' && $channels[1] eq 'Yposition' && $channels[2] eq 'Zposition') {
            my $v = GLM::Vec3->new(@positions[0..2]);
            $model_matrix = GLM::Functions::translate($model_matrix, $v);
            for (my $i = 3; $i < 6; ++$i) {
                if ($channels[$i] =~ /([XYZ])rotation/) {
                    $model_matrix = GLM::Functions::rotate($model_matrix, deg2rad($positions[$i]), $axis{$1});
                } else {
                    die "$channels[$i]: not rotation?";
                }
            }
        } else {
            die 'not position?';
        }
    } else {
        for (my $i = 0; $i < 3; ++$i) {
            if ($channels[$i] =~ /([XYZ])rotation/) {
                $model_matrix = GLM::Functions::rotate($model_matrix, deg2rad($positions[$i]), $axis{$1});
            } else {
                die "$channels[$i]: not rotation?";
            }
        }
    }
    $this->shader->set_mat4('model', $model_matrix);
    if (exists($this->{buffer}{$joint->name})) {
        $this->{buffer}{$joint->name}->bind;
        my $count = $this->{count}{$joint->name};

        # lines
        #glDrawArrays(GL_LINES, 0, $count);
        
        # cube
        glDrawArrays(GL_TRIANGLES, 0, $count);
    }
    for ($joint->children) {
        $this->draw_joint($_, $model_matrix);
    }
}

#   a                e
#    +--------------+
#    |\              \
#    | \ d            \ h
#    |  +--------------+
#    |  |              |
#    +  |           +  |
#   b \ |          f   |
#      \|              |
#       +--------------+
#      c                g
#       
#    e3 |
#       |  e1
#       +----
#        \
#      e2 \
sub create_cube {
    my $w = 3.0;
    my @vertices;

    my $p1 = GLM::Vec3->new(0);
    my $p2 = GLM::Vec3->new(@_);
    my $e1 = $p2->normalized;
    my $e2 = GLM::Vec3->new(0, 0, 1);
    if ($e1->dot($e2) > 1 - 1e-8) {
        $e2 = GLM::Vec3->new(-1, 0, 0);
    }
    my $e3 = $e2->cross($e1);
    $e2 = $e1->cross($e3);
    $e1->normalize;
    $e2->normalize;
    $e3->normalize;

    my ($a, $b, $c, $d, $e, $f, $g, $h);
    my (@a, @b, @c, @d, @e, @f, @g, @h);
    $a = $p1 - $w * $e2 + $w * $e3;
    @a = ($a->x, $a->y, $a->z);
    $b = $p1 - $w * $e2 - $w * $e3;
    @b = ($b->x, $b->y, $b->z);
    $c = $p1 + $w * $e2 - $w * $e3;
    @c = ($c->x, $c->y, $c->z);
    $d = $p1 + $w * $e2 + $w * $e3;
    @d = ($d->x, $d->y, $d->z);
    $e = $p2 - $w * $e2 + $w * $e3;
    @e = ($e->x, $e->y, $e->z);
    $f = $p2 - $w * $e2 - $w * $e3;
    @f = ($f->x, $f->y, $f->z);
    $g = $p2 + $w * $e2 - $w * $e3;
    @g = ($g->x, $g->y, $g->z);
    $h = $p2 + $w * $e2 + $w * $e3;
    @h = ($h->x, $h->y, $h->z);

    my @n1 = (-$e1->x, -$e1->y, -$e1->z);
    push @vertices, @a, @n1, @b, @n1, @c, @n1;
    push @vertices, @c, @n1, @d, @n1, @a, @n1;

    my @n2 = ($e1->x, $e1->y, $e1->z);
    push @vertices, @g, @n2, @f, @n2, @e, @n2;
    push @vertices, @e, @n2, @h, @n2, @g, @n2;

    my @n3 = ($e2->x, $e2->y, $e2->z);
    push @vertices, @d, @n3, @c, @n3, @g, @n3;
    push @vertices, @g, @n3, @h, @n3, @d, @n3;

    my @n4 = (-$e2->x, -$e2->y, -$e2->z);
    push @vertices, @f, @n4, @b, @n4, @a, @n4;
    push @vertices, @a, @n4, @e, @n4, @f, @n4;

    my @n5 = ($e3->x, $e3->y, $e3->z);
    push @vertices, @a, @n5, @d, @n5, @h, @n5;
    push @vertices, @h, @n5, @e, @n5, @a, @n5;

    my @n6 = (-$e3->x, -$e3->y, -$e3->z);
    push @vertices, @g, @n6, @c, @n6, @b, @n6;
    push @vertices, @b, @n6, @f, @n6, @g, @n6;

    @vertices;
}

sub cube_mesh {
    my ($lx, $ly, $lz) = map $_ / 2, @_;
    my ($a, $b, $c, $d, $e, $f, $g, $h);
    #   a                e
    #    +--------------+
    #    |\              \
    #    | \ d            \ h
    #    |  +--------------+
    #    |  |              |
    #    +  |           +  |
    #   b \ |          f   |
    #      \|              |
    #       +--------------+
    #      c                g
    #       
    #    y  |
    #       |  x
    #       +----
    #        \
    #      z  \
    $a = GLM::Vec4->new(-$lx,  $ly, -$lz, 1);
    $b = GLM::Vec4->new(-$lx, -$ly, -$lz, 1);
    $c = GLM::Vec4->new(-$lx, -$ly,  $lz, 1);
    $d = GLM::Vec4->new(-$lx,  $ly,  $lz, 1);
    $e = GLM::Vec4->new( $lx,  $ly, -$lz, 1);
    $f = GLM::Vec4->new( $lx, -$ly, -$lz, 1);
    $g = GLM::Vec4->new( $lx, -$ly,  $lz, 1);
    $h = GLM::Vec4->new( $lx,  $ly,  $lz, 1);

    my ($nx, $ny, $nz);
    my @vlist;
    $nx = GLM::Vec4->new(1, 0, 0, 0);
    $ny = GLM::Vec4->new(0, 1, 0, 0);
    $nz = GLM::Vec4->new(0, 0, 1, 0);

    push @vlist, $a, -$nx, $b, -$nx, $c, -$nx;
    push @vlist, $c, -$nx, $d, -$nx, $a, -$nx;

    push @vlist, $g,  $nx, $f,  $nx, $e,  $nx;
    push @vlist, $e,  $nx, $h,  $nx, $g,  $nx;

    push @vlist, $d,  $nz, $c,  $nz, $g,  $nz;
    push @vlist, $g,  $nz, $h,  $nz, $d,  $nz;

    push @vlist, $f, -$nz, $b, -$nz, $a, -$nz;
    push @vlist, $a, -$nz, $e, -$nz, $f, -$nz;

    push @vlist, $a,  $ny, $d,  $ny, $h,  $ny;
    push @vlist, $h,  $ny, $e,  $ny, $a,  $ny;

    push @vlist, $g, -$ny, $c, -$ny, $b, -$ny;
    push @vlist, $b, -$ny, $f, -$ny, $g, -$ny;
    @vlist;
}

sub sphere_mesh {
    my ($xo, $yo, $zo, $r, $s) = @_; # x, y, z, radius, slice
    my @vlist;
    for (my $i = 0; $i < $s; ++$i) {
        my $theta1 = pi / $s * $i;
        my $theta2 = pi / $s * ($i + 1);
        my $y1 = cos($theta1);
        my $y2 = cos($theta2);
        my $r1 = sin($theta1);
        my $r2 = sin($theta2);
        for (my $j = 0; $j < $s * 2; ++$j) {
            my $phi1 = pi / $s * $j;
            my $phi2 = pi / $s * ($j + 1);
            my $za = $r1 * cos($phi1);
            my $xa = $r1 * sin($phi1);
            my $zb = $r2 * cos($phi1);
            my $xb = $r2 * sin($phi1);
            my $zc = $r2 * cos($phi2);
            my $xc = $r2 * sin($phi2);
            my $zd = $r1 * cos($phi2);
            my $xd = $r1 * sin($phi2);
            my ($a, $b, $c, $d, $n);
            $a = GLM::Vec3->new($xa, $y1, $za);
            $b = GLM::Vec3->new($xb, $y2, $zb);
            $c = GLM::Vec3->new($xc, $y2, $zc);
            $d = GLM::Vec3->new($xd, $y1, $zd);
            $n = $a + $b + $c + $d;
            $n->normalize;
            $n = GLM::Vec4->new($n->x, $n->y, $n->z, 0);
            $a *= $r;
            $b *= $r;
            $c *= $r;
            $d *= $r;
            my $o = GLM::Vec3->new($xo, $yo, $zo);
            $a += $o;
            $b += $o;
            $c += $o;
            $d += $o;
            $a = GLM::Vec4->new($a->x, $a->y, $a->z, 1);
            $b = GLM::Vec4->new($b->x, $b->y, $b->z, 1);
            $c = GLM::Vec4->new($c->x, $c->y, $c->z, 1);
            $d = GLM::Vec4->new($d->x, $d->y, $d->z, 1);
            push @vlist, $a, $n;
            push @vlist, $b, $n;
            push @vlist, $c, $n;
            push @vlist, $c, $n;
            push @vlist, $d, $n;
            push @vlist, $a, $n;
        }
    }
    @vlist;
}

sub load_geometry_config {
    my $this = shift;
    my $filename = shift;
    open my $fh_in, '<', $filename;
    my $state = 0;
    my @vlist;
    my ($node, $translate, $rotate);
    while (<$fh_in>) {
        chomp;
        next if /^#/ or /^\s*$/;

        if ($state == 0) {
            @vlist = ();
            my @list = split;
            my $shape = shift @list;
            if ($shape eq 'cube') {
                push @vlist, cube_mesh(@list);
            } elsif ($shape eq 'sphere') {
                push @vlist, sphere_mesh(@list);
            } else {
                croak "$list[0]: not implemented\n";
            }
        } elsif ($state == 1) {
            $node = $_;
        } elsif ($state == 2) {
            $translate = GLM::Functions::translate($identity_mat, GLM::Vec3->new(split));
        } elsif ($state == 3) {
            my ($rx, $ry, $rz) = split;
            $rotate = GLM::Functions::rotate($identity_mat, $rx, $axis{X}) * GLM::Functions::rotate($identity_mat, $ry, $axis{Y}) * GLM::Functions::rotate($identity_mat, $rz, $axis{Z});
            push @{$this->{geometry_config}{$node}}, map { my $v = $translate * $rotate * $_; ($v->x, $v->y, $v->z); } @vlist;
        }

        $state = ($state + 1) % 4;
    }
    close $fh_in;
}

1;
