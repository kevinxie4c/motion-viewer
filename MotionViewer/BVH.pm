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
    my $this = $class->SUPER::load(@_);
    $this->frame(0);
    
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
        for ($joint->children) {
            push @vertices, &create_cube($_->offset);
        }
        if ($joint->end_site) {
            push @vertices, &create_cube($joint->end_site);
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

sub frame{
    my $this = shift;
    $this->{frame} = shift if @_;
    $this->{frame};
}

sub shader {
    my $this = shift;
    $this->{shader} = shift if @_;
    $this->{shader};
}

sub camera {
    my $this = shift;
    $this->{camera} = shift if @_;
    $this->{camera};
}
    
sub draw {
    my $this = shift;
    $this->shader->use;
    $this->shader->set_mat4('view', $this->camera->view_matrix);
    $this->shader->set_mat4('proj', $this->camera->proj_matrix);
    my $model_matrix = GLM::Mat4->new(
        1, 0, 0, 0, 
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    );
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
    my @positions = $joint->at_frame($this->frame);
    #my @positions = (0) x 6;
    #if ($joint->name eq 'LeftUpArm' || $joint->name eq 'RightUpArm') {
    #    $positions[1] = 45;
    #}
    #if ($joint->name eq 'LeftLowArm') {
    #    $positions[0] = 45;
    #}
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
    my $w = 1.0;
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

    push @vertices, @a, @b, @c;
    push @vertices, -$e1->x, -$e1->y, -$e1->z;
    push @vertices, @c, @d, @a;
    push @vertices, -$e1->x, -$e1->y, -$e1->z;

    push @vertices, @e, @f, @g;
    push @vertices, $e1->z, $e1->y, $e1->z;
    push @vertices, @g, @h, @e;
    push @vertices, $e1->z, $e1->y, $e1->z;

    push @vertices, @d, @c, @g;
    push @vertices, $e2->z, $e2->y, $e2->z;
    push @vertices, @g, @h, @d;
    push @vertices, $e2->z, $e2->y, $e2->z;

    push @vertices, @a, @b, @f;
    push @vertices, -$e2->z, -$e2->y, -$e2->z;
    push @vertices, @f, @e, @a;
    push @vertices, -$e2->z, -$e2->y, -$e2->z;

    push @vertices, @a, @d, @h;
    push @vertices, $e3->x, $e3->y, $e3->z;
    push @vertices, @h, @e, @a;
    push @vertices, $e3->x, $e3->y, $e3->z;

    push @vertices, @b, @c, @g;
    push @vertices, -$e3->x, -$e3->y, -$e3->z;
    push @vertices, @g, @f, @b;
    push @vertices, -$e3->x, -$e3->y, -$e3->z;

    @vertices;
}

1;
