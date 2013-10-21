=head1 NAME

C<Gearman::JobScheduler::Admin> - Gearman administration utilities.

Reimplements functionality of "gearadmin"
(http://bazaar.launchpad.net/~tangent-trunk/gearmand/1.2/view/head:/bin/gearadmin.cc)
in Perl.

=cut
package Gearman::JobScheduler::Admin;

use strict;
use warnings;
use Modern::Perl "2012";

use Gearman::JobScheduler;
use Gearman::JobScheduler::Configuration;

# Neither "Gearman" nor "Gearman::XS" modules provide the administration
# functionality, so we'll connect directly to Gearman and send / receive
# commands ourselves.
use Net::Telnet;

# Connection timeout
use constant GJS_ADMIN_TIMEOUT => 10;


=head2 (static) C<server_version($config)>

Get the version number from all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns hashref of configured servers and their versions, e.g.:

=begin text

	{
		'localhost:4730' => '1.1.9',
		# ...
	}

=end text

Returns C<undef> on error.

=cut
sub server_version($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	my $versions = {};

	foreach my $server (@{$config->gearman_servers}) {

		my $version = server_version_on_server($server);
		unless (defined $version) {
			say STDERR "Unable to determine version of server $server.";
			return undef;
		}

		$versions->{ $server } = $version;
	}

	return $versions;
}


=head2 (static) C<server_version_on_server($server)>

Get the version number from a server.

Parameters:

=over 4

=item * Server as "host:port" (e.g. "localhost:4730")

=back

Returns a string server version, e.g. '1.1.9'.

Returns C<undef> on error.

=cut
sub server_version_on_server($)
{
	my $server = shift;

	my $telnet = _net_telnet_instance_for_server($server);

	$telnet->print('version');
	my $version = $telnet->getline();
	chomp $version;

	unless ($version =~ /^OK /) {
		say STDERR "Server $server didn't respond with 'OK': $version";
		return undef;
	}

	$version =~ s/^OK //;
	unless ($version) {
		say STDERR "Version string is empty.";
		return undef;
	}

	return $version;
}


=head2 (static) C<server_verbose($config)>

Get the verbose setting from all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns hashref of configured servers and their verbosity levels, e.g.:

=begin text

	{
		'localhost:4730' => 'ERROR',
		# ...
	}

=end text

Available verbosity levels:

=over 4

* C<FATAL>

* C<ALERT> (currently unused in Gearman)

* C<CRITICAL> (currently unused in Gearman)

* C<ERROR>

* C<WARN>

* C<NOTICE>

* C<INFO>

* C<DEBUG>

=back

Returns C<undef> on error.

=cut
sub server_verbose($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	my $verbose_levels = {};

	foreach my $server (@{$config->gearman_servers}) {

		my $verbose = server_verbose_on_server($server);
		unless (defined $verbose) {
			say STDERR "Unable to determine verbosity level of server $server.";
			return undef;
		}

		$verbose_levels->{ $server } = $verbose;
	}

	return $verbose_levels;
}


=head2 (static) C<server_verbose_on_server($server)>

Get the verbose setting from a server.

Parameters:

=over 4

=item * Server as "host:port" (e.g. "localhost:4730")

=back

Returns string verbose setting (see C<server_verbose> for possible values).

Returns C<undef> on error.

=cut
sub server_verbose_on_server($)
{
	my $server = shift;

	my $telnet = _net_telnet_instance_for_server($server);

	$telnet->print('verbose');
	my $verbose = $telnet->getline();
	chomp $verbose;

	unless ($verbose =~ /^OK /) {
		say STDERR "Server $server didn't respond with 'OK': $verbose";
		return undef;
	}

	$verbose =~ s/^OK //;
	unless ($verbose) {
		say STDERR "Verbose string is empty.";
		return undef;
	}

	return $verbose;
}


=head2 (static) C<create_function($function_name, $config)>

Create the function on all the configured servers.

Parameters:

=over 4

=item * Function name (e.g. C<hello_world>)

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns true (1) if the function has been created, false (C<undef>) on error.

=cut
sub create_function($$)
{
	my ($function_name, $config) = @_;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<drop_function($function_name, $config)>

Drop the function from the server.

Parameters:

=over 4

=item * Function name (e.g. C<hello_world>)

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns true (1) if the function has been dropped, false (C<undef>) on error.

=cut
sub drop_function($$)
{
	my ($function_name, $config) = @_;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<show_jobs($config)>

Show all jobs on all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns a hashref of job statuses, e.g.:

=begin text

	{
		# Gearman job ID that was passed as a parameter
		'H:tundra.home:8' => {

			# Whether or not the job is currently running
			'running' => 1,

			# Numerator and denominator of the job's progress
			# (in this example, job is 1333/2000 complete)
			'numerator' => 1333,	# 0 if the job haven't been started yet
			'denominator' => 2000	# 1 if the job haven't been started yet
			
		},

		# ...

	};

=end text

Returns C<undef> on error.

=cut
sub show_jobs($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<show_unique_jobs($config)>

Show unique jobs on all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns an arrayref of unique job identifiers, e.g.:

=begin text

	[
		# SHA256 hashes of "function_name(params)" strings as generated by GJS
		'1455d13e979c2c94445a47d2fed0854557c3afb195aceb55286c304d2dd86a8',
		'fe9ffb3eee42b1f983a974e5a68d263ac0930ac0d5fda57a253238243a981b3',
		'184e1c19a67d84fbeac1e1affab7ce725c8fb427a78ef203a15a67648b6eb60',
	]

=end text

Returns C<undef> on error.

=cut
sub show_unique_jobs($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<cancel_job($gearman_job_id, $config)>

Remove a given job from all the configured servers' queues.

Parameters:

=over 4

=item * Gearman job ID (e.g. "H:localhost.localdomain:8")

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns true (1) if the job has been cancelled, false (C<undef>) on error.

=cut
sub cancel_job($$)
{
	my ($gearman_job_id, $config) = @_;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<get_pid($config)>

Get Process ID for all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns integer PID (e.g. 1234).

Returns C<undef> on error.

=cut
sub get_pid($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<status($config)>

Get status from all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns a hashref of Gearman functions and their statuses, e.g.:

=begin text

	{
		# Gearman function name
		'NinetyNineBottlesOfBeer' => {

			# Number of enqueued (waiting to be run) jobs
			'total'	=> 4,

			# Number of currently running jobs
			'running' => 1,

			# Number of currently registered workers
			'available_workers' => 1
			
		},

		# ...

	};

=end text

Returns C<undef> on error.

=cut
sub status($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

	# FIXME not implemented
}


=head2 (static) C<workers($config)>

Get a list of workers from all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns an arrayref of hashrefs for each of the registered worker, e.g.:

=begin text

	[
		{
			# Unique integer file descriptor of the worker
			'file_descriptor' => 23,
			
			# IP address of the worker
			'ip_address' => '127.0.0.1',

			# Client ID of the worker (might be undefined)
			'client_id' => undef,

			# List of functions the worker covers
			'functions' => [
				'NinetyNineBottlesOfBeer',
				'Addition'
			]
		},
		# ...
	]

=end text

Returns C<undef> on error.

=cut
sub workers($)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

}


=head2 (static) C<shutdown($config)>

Shutdown all the configured servers.

Parameters:

=over 4

=item * Instance of Gearman::JobScheduler::Configuration

=back

Returns true (1) if the Gearman server has been shutdown, false (C<undef>) on error.

=cut
sub shutdown(;$)
{
	my $config = shift;

	unless ($config) {
		die "Configuration is undefined.";
	}

}


# Connects to Gearman, returns Net::Telnet instance
sub _net_telnet_instance_for_server($)
{
	my $server = shift;

	my ($host, $port) = split(':', $server);
	$port //= 4730;

	my $telnet = new Net::Telnet(Host => $host,
								 Port => $port,
								 Timeout => GJS_ADMIN_TIMEOUT);
	$telnet->open();

	return $telnet;
}


1;
