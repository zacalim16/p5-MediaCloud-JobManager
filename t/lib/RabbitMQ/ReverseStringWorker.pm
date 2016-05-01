package RabbitMQ::ReverseStringWorker;

use strict;
use warnings;

use lib qw|lib/ t/lib/ t/lib/RabbitMQ/ t/brokers/|;

use Moose;
with 'RabbitMQ::TestWorker', 'ReverseStringWorker' => { -excludes => [ 'configuration' ], };

no Moose;

__PACKAGE__;
