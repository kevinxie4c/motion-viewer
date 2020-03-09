package MotionViewer::Shader;

use OpenGL::Modern qw(:all);
use OpenGL::Array;
use File::Slurp;

sub load {
    my ($class, $vs_name, $fs_name) = @_;
    my $this = bless {}, $class;
    my $vextex = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource_p($vextex, read_file($vs_name));
    glCompileShader($vextex);
    my $success_ptr = OpenGL::Array->new(1, GL_FLOAT);
    glGetShaderiv_c($vextex, GL_COMPILE_STATUS, $success_ptr->ptr);
    my ($success) = $success_ptr->retrieve(0, 1);
    if (!$success) {
        my $info = "\x00" x 1024;
        glGetShaderInfoLog_c($vextex, 1024, 0, $info);
        $info =~ s/\0.*//sg;
        die "$vs_name:\n$info";
    }
    my $fragment = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource_p($fragment, read_file($fs_name));
    glCompileShader($fragment);
    glGetShaderiv_c($fragment, GL_COMPILE_STATUS, $success_ptr->ptr);
    ($success) = $success_ptr->retrieve(0, 1);
    if (!$success) {
        my $info = "\x00" x 1024;
        glGetShaderInfoLog_c($fragment, 1024, 0, $info);
        $info =~ s/\0.*//sg;
        die "$fs_name:\n$info";
    }
    my $shader = glCreateProgram();
    glAttachShader($shader, $vextex);
    glAttachShader($shader, $fragment);
    glLinkProgram($shader);
    glGetProgramiv_c($shader, GL_LINK_STATUS, $success_ptr->ptr);
    ($success) = $success_ptr->retrieve(0, 1);
    if (!$success) {
        my $info = "\x00" x 1024;
        glGetProgramInfoLog_c($shader, 1024, 0, $info);
        $info =~ s/\0.*//sg;
        die "linking:\n$info";
    }
    glDeleteShader($vextex);
    glDeleteShader($fragment);
    $this->{shader} = $shader;
    $this;
}

sub use {
    glUseProgram($_[0]->{shader});
}

sub set_int {
    my ($this, $name, $value) = @_;
    glUniform1i(glGetUniformLocation_c($this->{shader}, $name), $value);
}

sub set_float {
    my ($this, $name, $value) = @_;
    glUniform1f(glGetUniformLocation_c($this->{shader}, $name), $value);
}

sub set_vec3 {
    my ($this, $name, $value) = @_;
    glUniform3fv_c(glGetUniformLocation_c($this->{shader}, $name), 1, $value->pointer);
}

sub set_vec4 {
    my ($this, $name, $value) = @_;
    glUniform4fv_c(glGetUniformLocation_c($this->{shader}, $name), 1, $value->pointer);
}

sub set_mat4 {
    my ($this, $name, $value) = @_;
    glUniformMatrix4fv_c(glGetUniformLocation_c($this->{shader}, $name), 1, 0, $value->pointer);
}

1;
