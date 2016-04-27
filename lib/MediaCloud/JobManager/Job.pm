
=head1 NAME

C<MediaCloud::JobManager::Job> - An abstract class for a "function".


=head1 LINGO

=over 4

=item * function

A function to be run by locally or remotely, e.g. C<add_default_feeds>.

=item * job

An instance of the function doing the actual job with specific parameters.

=back

=cut

package MediaCloud::JobManager::Job;

use strict;
use warnings;
use Modern::Perl "2012";
use feature qw(switch);

use Moose::Role 2.1005;

use MediaCloud::JobManager;    # helper subroutines
use MediaCloud::JobManager::Configuration;

use IO::File;
use Capture::Tiny ':all';
use Time::HiRes;
use Data::Dumper;
use DateTime;
use Readonly;
use Sys::Hostname;

# used for capturing STDOUT and STDERR output of each job and timestamping it;
# initialized before each job
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init(
    {
        level  => $DEBUG,
        utf8   => 1,
        layout => "%d{ISO8601} [%P]: %m%n"
    }
);

=head1 ABSTRACT INTERFACE

The following subroutines must be implemented by the subclasses of this class.

=head2 REQUIRED

=head3 C<run($self, $args)>

Run the job.

Parameters:

=over 4

=item * C<$self>, a reference to the instance of the function class

=item * (optional) C<$args> (hashref), arguments needed for running the
function

=back

An instance (object) of the class will be created before each run. Class
instance variables (e.g. C<$self-E<gt>_my_variable>) will be discarded after
each run.

Returns result on success (serializable by the L<JSON> module). The result will
be discarded if the job is added as a background process.

Provides progress reports when available:

=over 4

=item * by calling C<$self-E<gt>set_progress($numerator, $denominator)>

=back

C<die()>s on error.

Writes log to C<STDOUT> or C<STDERR> (preferably the latter).

=cut

requires 'run';

=head3 (static) C<retries()>

Return the number of retries for each job.

Returns a number of retries each job will be attempted at. For example, if the
number of retries is set to 3, the job will be attempted 4 four times in total.

Returns 0 if the job should not be retried (attempted only once).

Default implementation of this subroutine returns 0 (no retries).

=cut

sub retries()
{
    # By default the job will not be retried if it fails
    return 0;
}

=head3 (static) C<unique()>

Return true if the function is "unique" (only for remote requests).

Returns true if two or more jobs with the same parameters can not be run at the
same and instead should be merged into one.

Default implementation of this subroutine returns "true".

=cut

sub unique()
{
    # By default the jobs are "unique", e.g. if there's already an
    # "Addition({operand_a => 2, operand_b => 3})" job running, a new one won't
    # be initialized
    return 1;
}

=head3 (static) C<configuration()>

Return an instance or a subclass of C<MediaCloud::JobManager::Configuration> to
be used as default configuration by both workers and clients.

Workers and clients will still be able to override this configuration by
passing their own C<config> argument. This configuration will be used if no
such argument is present.

Default implementation of this subroutine returns an instance of
C<MediaCloud::JobManager::Configuration> (default configuration).

=cut

sub configuration()
{
    return MediaCloud::JobManager::Configuration->instance;
}

=head3 (static) C<priority()>

Return priority of the job ("low", "normal" or "high"). This will influence the
queueing mechanism and prioritize "high priority" jobs.

Returns one of the three constants:

=over 4

=item * C<MJM_JOB_PRIORITY_LOW()>, if the job is considered of "low priority".

=item * C<MJM_JOB_PRIORITY_NORMAL()> if the job is considered of "normal priority".

=item * C<MJM_JOB_PRIORITY_HIGH()> if the job is considered of "high priority".

=back

Default implementation of this subroutine returns C<MJM_JOB_PRIORITY_NORMAL()>
("normal priority" job).

=cut

# Job priorities (subroutines instead of constants because exporting
# constants with Moose in place is painful)
sub MJM_JOB_PRIORITY_LOW    { 'low' }
sub MJM_JOB_PRIORITY_NORMAL { 'normal' }
sub MJM_JOB_PRIORITY_HIGH   { 'high' }

sub priority()
{
    return MJM_JOB_PRIORITY_NORMAL();
}

=head1 HELPER SUBROUTINES

The following subroutines can be used by the deriving class.

=head2 C<$self-E<gt>set_progress($numerator, $denominator)>

Provide progress report while running the task (from C<run()>).

Examples:

=over 4

=item * C<$self-E<gt>set_progress(3, 10)>

3 out of 10 subtasks are complete.

=item * C<$self-E<gt>set_progress(45, 100)>

45 out of 100 subtasks are complete (or 45% complete).

=back

=cut

sub set_progress($$$)
{
    my ( $self, $numerator, $denominator ) = @_;

    unless ( defined $self->_job )
    {
        # Running the job locally, not going to report progress (because job is blocking)
        DEBUG( "Job is undef" );
        return;
    }
    unless ( $denominator )
    {
        die "Denominator is 0.";
    }

    my $function_name = $self->name();
    my $config        = $function_name->configuration();

    $config->{ broker }->set_job_progress( $self->_job, $numerator, $denominator );

    # Written to job's log
    say STDERR "$numerator/$denominator complete.";
}

=head1 CLIENT SUBROUTINES

The following subroutines can be used by clients to run a function.

=head2 (static) C<$class-E<gt>run_locally([$args, $config])>

Run locally and right away, blocking the parent process until the job is
finished.

Parameters:

=over 4

=item * (optional) C<$args> (hashref), arguments required for running the
function (serializable by the L<JSON> module)

=item * (optional, internal) job handle to be later used by send_progress()

=back

Returns result (may be false of C<undef>) on success, C<die()>s on error

=cut

sub run_locally($;$$)
{
    my ( $class, $args, $job ) = @_;

    if ( ref $class )
    {
        die "Use this subroutine as a static method, e.g. MyFunction->run_locally()";
    }

    my $function_name = $class->name();
    my $config        = $function_name->configuration();

    # say STDERR "Running locally";

    my $mjm_job_id;
    if ( $job )
    {
        my $job_id = $config->{ broker }->job_id_from_handle( $job );
        $mjm_job_id = MediaCloud::JobManager::_unique_path_job_id( $function_name, $args, $job_id );
    }
    else
    {
        $mjm_job_id = MediaCloud::JobManager::_unique_path_job_id( $function_name, $args );
    }
    unless ( $mjm_job_id )
    {
        die "Unable to determine unique MediaCloud::JobManager job ID";
    }

    my $starting_job_message = "Starting job ID \"$mjm_job_id\"...";
    my $finished_job_message;

    INFO( $starting_job_message );

    my $result;
    eval {

        my $d = Data::Dumper->new( [ $args ], [ 'args' ] );
        $d->Indent( 0 );
        my $str_arguments = $d->Dump;

        say STDERR $starting_job_message;
        say STDERR "========";
        say STDERR "Arguments: $str_arguments";
        say STDERR "========";
        say STDERR "";

        my $start = Time::HiRes::gettimeofday();

        my $job_succeeded = 0;
        for ( my $retry = 0 ; $retry <= $class->retries() ; ++$retry )
        {
            if ( $retry > 0 )
            {
                say STDERR "";
                say STDERR "========";
                say STDERR "Retrying ($retry)...";
                say STDERR "========";
                say STDERR "";
            }

            eval {

                # Try to run the job
                my $instance = $class->new();

                # _job is undef when running locally, instance when issued from worker
                $instance->_job( $job );

                # Do the work
                $result = $instance->run( $args );

                # Unset the _job for the sake of cleanliness
                $instance->_job( undef );

                # Destroy instance
                $instance = undef;

                $job_succeeded = 1;
            };

            if ( $@ )
            {
                say STDERR "Job \"$mjm_job_id\" failed: $@";
            }
            else
            {
                last;
            }
        }

        unless ( $job_succeeded )
        {
            my $job_failed_message = "Job \"$mjm_job_id\" failed" .
              ( $class->retries() ? " after " . $class->retries() . " retries" : "" ) . ": $@";

            say STDERR "";
            say STDERR "========";
            say STDERR $job_failed_message;
            die $job_failed_message;
        }

        my $end = Time::HiRes::gettimeofday();

        say STDERR "";
        say STDERR "========";
        $finished_job_message = "Finished job ID \"$mjm_job_id\" in " . sprintf( "%.2f", $end - $start ) . " seconds";
        say STDERR $finished_job_message;

    };

    my $error = $@;
    if ( $error )
    {
        # Write to job's log
        say STDERR "Job died: $error";
    }

    # Untie STDOUT / STDERR from Log4perl
    untie *STDERR;
    untie *STDOUT;

    if ( $finished_job_message )
    {
        INFO( $finished_job_message );
    }

    if ( $error )
    {
        # Print out to worker's STDERR and die()
        LOGDIE( "$error" );
    }

    return $result;
}

=head2 (static) C<$class-E<gt>run_remotely([$args])>

Run remotely, wait for the task to complete, return the result; block the
process until the job is complete.

Parameters:

=over 4

=item * (optional) C<$args> (hashref), arguments needed for running the
function (serializable by the L<JSON> module)

=back

Returns result (may be false of C<undef>) on success, C<die()>s on error

=cut

sub run_remotely($;$)
{
    my $class = shift;
    my $args  = shift;

    if ( ref $class )
    {
        die "Use this subroutine as a static method, e.g. MyFunction->run_remotely()";
    }

    my $function_name = $class->name;
    unless ( $function_name )
    {
        die "Unable to determine function name.";
    }

    my $config = $function_name->configuration();

    return $config->{ broker }->run_job_sync( $function_name, $args, $class->priority(), $class->unique() );
}

sub run_on_gearman
{
    my $class = shift;

    warn 'run_on_gearman() is deprecated, use run_remotely() instead.';

    return $class->run_remotely( @_ );
}

=head2 (static) C<$class-E<gt>add_to_queue([$args, $config])>

Add to queue remotely, do not wait for the task to complete, return
immediately; do not block the parent process until the job is complete.

Parameters:

=over 4

=item * (optional) C<$args> (hashref), arguments needed for running the
function (serializable by the L<JSON> module)

=back

Returns job ID if the job was added to queue successfully, C<die()>s on error.

=cut

sub add_to_queue($;$)
{
    my $class = shift;
    my $args  = shift;

    if ( ref $class )
    {
        die "Use this subroutine as a static method, e.g. MyFunction->add_to_queue()";
    }

    my $function_name = $class->name;
    unless ( $function_name )
    {
        die "Unable to determine function name.";
    }

    my $config = $function_name->configuration();

    return $config->{ broker }->run_job_async( $function_name, $args, $class->priority(), $class->unique() );
}

sub enqueue_on_gearman
{
    my $class = shift;

    warn 'enqueue_on_gearman() is deprecated, use add_to_queue() instead.';

    return $class->add_to_queue( @_ );
}

=head2 (static) C<name()>

Returns function's name (e.g. C<NinetyNineBottlesOfBeer>).

Usage:

	NinetyNineBottlesOfBeer->name();

Parameters:

=over 4

=item * Class or class instance

=back

=cut

sub name($)
{
    my $self_or_class = shift;

    my $function_name = '';
    if ( ref( $self_or_class ) )
    {
        # Instance
        $function_name = '' . ref( $self_or_class );
    }
    else
    {
        # Static
        $function_name = $self_or_class;
    }

    if ( $function_name eq 'Job' )
    {
        die "Unable to determine function name.";
    }

    return $function_name;
}

# Worker will pass this parameter to run_locally() which, in turn, will
# temporarily place job handle to this variable so that set_progress() helper
# can later use it
has '_job' => ( is => 'rw' );

no Moose;    # gets rid of scaffolding

1;