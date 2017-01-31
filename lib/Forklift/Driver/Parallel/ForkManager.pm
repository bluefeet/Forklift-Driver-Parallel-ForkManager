package Forklift::Driver::Parallel::ForkManager;

=head1 NAME

Forklift::Driver::Parallel::ForkManager - Run Forklift jobs in parallel using forks.

=head1 SYNOPSIS

    use Forklift;
    my $lift = Forklift->new(
        driver => {
            class       => '::Parallel::ForkManager',
            max_workers => 5,
            wait_sleep  => 0.5,
        },
    );

=head1 DESCRIPTION

This is a driver for L<Forklift> which runs jobs in parallel using
L<Parallel::ForkManager>.

This driver consumes the L<Forklift::Driver> role and provides the full
interface as documented there.

=cut

use Parallel::ForkManager;
use Types::Common::Numeric -types;
use Scalar::Util qw( weaken );

use Moo;
use strictures 2;
use namespace::clean;

with 'Forklift::Driver';

my $last_id = 0;
my $max_id = 4_000_000_000;
sub _next_id {
    $last_id ++;
    $last_id = 1 if $last_id > $max_id;
    return "worker-$last_id";
}

has _worker_jobs => (
    is      => 'ro',
    default => sub{ {} },
);

sub _build_finish_callback {
    my ($self) = @_;

    # Avoid leaks.
    weaken $self;

    return sub{
        my ($pid, $exit, $id, $signal, $core_dump, $raw_results) = @_;

        my $result_class = $self->result_class();
        my $jobs = delete $self->_worker_jobs->{$id};

        foreach my $job (@$jobs) {
            my $result = shift( @$raw_results );
            $result = $result_class->new(
                %$result,
                job_id => $job->id(),
            );
            $job->run_callback( $result );
        }

        return;
    };
};

has _pfm => (
    is       => 'lazy',
    init_arg => undef,
    builder  => '_build_pfm',
);
sub _build_pfm {
    my ($self) = @_;

    my $pfm = Parallel::ForkManager->new(
        $self->max_workers(),
    );

    $pfm->run_on_finish( $self->_build_finish_callback() );

    $pfm->set_waitpid_blocking_sleep( $self->wait_sleep() );

    return $pfm;
}

sub DEMOLISH {
    my ($self) = @_;
    return if !$self->_pfm();
    return if $self->in_job();
    $self->wait_all();
    return;
}

=head1 OPTIONAL ARGUMENTS

=head2 max_workers

The number of maximum child processes to fork.  Defaults to C<10>.

=cut

has max_workers => (
    is      => 'ro',
    isa     => PositiveOrZeroInt,
    default => 10,
);

=head2 wait_sleep

How long to sleep between wait checks.  This is used to set the
C<set_waitpid_blocking_sleep> on the L<Parallel::ForkManager>
object.

=cut

has wait_sleep => (
    is      => 'ro',
    isa     => PositiveOrZeroNum,
    default => 1,
);

=head1 ATTRIBUTES

=head2 is_busy

Returns true if C<running_procs> in L<Parallel::ForkManager> is
non-empty.

=cut

sub is_busy {
    my ($self) = @_;
    return ($self->_pfm->running_procs() > 0) ? 1 : 0;
}

=head2 is_saturated

Returns true if the number of PIDs in C<running_procs> is less
than the value of C<max_procs> (AKA L</max_workers>) in
L<Parallel::ForkManager>.

=cut

sub is_saturated {
    my ($self) = @_;
    my $pfm = $self->_pfm();
    return ($pfm->running_procs() < $pfm->max_procs()) ? 0 : 1;
}

=head2 in_job

Returns true if C<is_child> from L<Parallel::ForkManager> returns true.

=cut

sub in_job {
    my ($self) = @_;
    return ($self->_pfm->is_child()) ? 1 : 0;
}

=head2 run_jobs

Takes a list of jobs and runs them together inside a single
L<Parallel::ForkManager> process.  This will block if
L</is_saturated> is true.

=cut

sub run_jobs {
    my ($self, @jobs) = @_;

    my $id = _next_id();
    $self->_worker_jobs->{$id} = \@jobs;

    my $pfm = $self->_pfm();
    $pfm->start( $id ) and return;

    my @results;

    foreach my $job (@jobs) {
        push @results, $job->run();
    }

    $pfm->finish( 0, \@results );
}

=head2 yield

Calls C<reap_finished_children> in L<Parallel::ForkManager>.

=cut

sub yield {
    my ($self) = @_;
    $self->_pfm->reap_finished_children();
    return;
}

=head2 wait_one

Waits for there to be one less active worker than there was
when the wait started.

=cut

sub wait_one {
    my ($self) = @_;
    my $pfm = $self->_pfm();
    my $running_procs = $pfm->running_procs() + 0;
    return if $running_procs == 0;
    my $available_procs = $pfm->max_procs - $running_procs;
    $pfm->wait_for_available_procs( $available_procs + 1 );
    return;
}

=head2 wait_all

Waits for all active workers to finish.

=cut

sub wait_all {
    my ($self) = @_;
    my $pfm = $self->_pfm();
    return if !$self->is_busy();
    $pfm->wait_all_children();
    return;
}

=head2 wait_saturated

Waits for there to be at least one available worker slot.

=cut

sub wait_saturated {
    my ($self) = @_;
    my $pfm = $self->_pfm();
    return if !$self->is_saturated();
    $pfm->wait_for_available_procs( 1 );
    return;
}

1;
__END__

=head1 SUPPORT

Feature requests, pull requests, and discussion can be had on GitHub at
L<https://github.com/bluefeet/Forklift-Driver-Parallel-ForkManager>.  You
are also welcome to email the author directly.

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

