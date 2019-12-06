package MotionViewer::BVH;

use parent 'Mocap::BVH';
use OpenGL::Modern qw(:all);
use GLM;
use Carp;

sub load {
    my $class = shift;
    my $this = $class->SUPER::load(@_);
    $this->time(0);
    $this->{shader} = MotionViewer::Shader->load('simple.vs', 'simple.fs');
    
    for my $joint($this->joints) {
        my @vertices;
        for ($joint->children) {
            push @vertices, (0, 0, 0, $_->offset);
        }
        if ($joint->end_site) {
            push @vertices, (0, 0, 0, $joint->end_site);
        }
        #print $joint->name, " @vertices\n";
        if (@vertices) {
            $this->{buffer}{$joint->name} = MotionViewer::Buffer->new(1, @vertices);
            $this->{count}{$joint->name} = @vertices / 3;
        }
    }

    $this;
}

sub time {
    my $this = shift;
    $this->{time} = shift if @_;
    $this->{time};
}

sub shader {
    my $this = shift;
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
    my @positions = $joint->at_time($this->time);
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
            #$model_matrix = GLM::Functions::translate($model_matrix, $v);
            for (my $i = 3; $i < 6; ++$i) {
            #for (my $i = 5; $i >= 3; --$i) {
                if ($channels[$i] =~ /([XYZ])rotation/) {
                    #$model_matrix = GLM::Functions::rotate($model_matrix, $positions[$i], $axis{$1});
                } else {
                    die "$channels[$i]: not rotation?";
                }
            }
        } else {
            die 'not position?';
        }
    } else {
        for (my $i = 0; $i < 3; ++$i) {
        #for (my $i = 2; $i >= 0; --$i) {
            if ($channels[$i] =~ /([XYZ])rotation/) {
                $model_matrix = GLM::Functions::rotate($model_matrix, $positions[$i], $axis{$1});
            } else {
                die "$channels[$i]: not rotation?";
            }
        }
    }
    $this->shader->set_mat4('model', $model_matrix);
    if (exists($this->{buffer}{$joint->name})) {
        $this->{buffer}{$joint->name}->bind;
        my $count = $this->{count}{$joint->name};
        glDrawArrays(GL_LINES, 0, $count);
    }
    for ($joint->children) {
        $this->draw_joint($_, $model_matrix);
    }
}

1;
