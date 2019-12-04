package MotionViewer::Camera;

use GLM;
use Math::Trig;

sub new {
    my $class = shift;
    my $this = bless {@_}, $class;
    $this->yaw(0) unless defined $this->{yaw};
    $this->pitch(0) unless defined $this->{pitch};
    $this->center(GLM::Vec3->new(0)) unless defined $this->{center};
    $this->distance(1) unless defined $this->{distance};
    $this->up(GLM::Vec3->new(0, 1, 0));
    $this->update_view_matrix;
    $this;
}

sub yaw {
    my $this = shift;
    $this->{yaw} = shift if @_;
    $this->{yaw};
}

sub pitch {
    my $this = shift;
    $this->{pitch} = shift if @_;
    if ($this->{pitch} > 90) {
        $this->{pitch} = 90;
    } elsif ($this->{pitch} < -90) {
        $this->{pitch} = -90;
    }
    $this->{pitch};
}

sub center {
    my $this = shift;
    $this->{center} = shift if @_;
    $this->{center};
}

sub up {
    my $this = shift;
    $this->{up} = shift if @_;
    $this->{up};
}

sub distance {
    my $this = shift;
    $this->{distance} = shift if @_;
    if ($this->{distance} < 1e-2) {
        $this->{distance} = 1e-2;
    }
    $this->{distance};
}

sub update_view_matrix {
    my $this = shift;
    my $pitch = deg2rad $this->pitch;
    my $yaw = deg2rad $this->yaw;
    my $y = sin $pitch;
    my $r = cos $pitch;
    my $x = $r * sin($yaw);
    my $z = $r * cos($yaw);
    my $d = GLM::Vec3->new($x, $y, $z) * $this->distance;
    my $eye = $this->center + $d;
    $this->{view_matrix} = GLM::Functions::lookAt($eye, $this->center, $this->up);
}

sub view_matrix {
    my $this = shift;
    $this->{view_matrix};
}

sub mouse_handler {
    my ($this, $button, $state, $x, $y) = @_;
    if ($state = GLUT_DOWN) {
        if ($button == GLUT_LEFT_BUTTON) {
            $this->{left_button} = 1;
        } elsif ($button == GLUT_RIGHT_BUTTON) {
            $this->{right_button} = 1;
        }
    } elsif ($state = GLUT_UP) {
        if ($button == GLUT_LEFT_BUTTON) {
            $this->{left_button} = 0;
        } elsif ($button == GLUT_RIGHT_BUTTON) {
            $this->{right_button} = 0;
        }
    }
    $this->{last_x} = $x;
    $this->{last_y} = $y;
}

sub motion_handler {
    my ($this, $x, $y) = @_;
    my $x_offset = $x - $this->{last_x};
    my $y_offset = $y - $this->{last_y};
    print 'yaw: ' . $this->yaw . "\n";
    print 'pitch: ' . $this->pitch . "\n";
    if ($this->{left_button}) {
        my $rot_speed = 0.1;
        $this->yaw($this->yaw + $x_offset * $rot_speed);
        $this->pitch($this->pitch - $y_offset * $rot_speed);
    } elsif ($this->{right_button}) {
        $zoom_speed = 0.1;
        $this->distance($this->distance + $y_offset * $zoom_speed);
    }
    $this->update_view_matrix;
    $this->{last_x} = $x;
    $this->{last_y} = $y;
}

1;
