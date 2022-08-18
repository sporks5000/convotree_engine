package ConvoTreeEngine::Mysql::Connect;

use strict;
use warnings;

use DBI;

our $dbHandler;
our %tableHash;

### The user will have to fill in this data
our $dbName = '';
our $dbHost = '';
our $dbUser = '';
our $dbPass = '';

sub getConnection {
	my $class = shift;

	if (!defined $dbHandler) {
		if (!$dbName || !$dbHost || !$dbUser || !$dbPass) {
			ConvoTreeEngine::Exception::Configuration->throw(
				error => 'The database connection is not configured',
			);
		}

		%tableHash = ();

		eval {
			$dbHandler = DBI->connect("DBI:mysql:database=" . $dbName . ";" . $dbHost, $dbUser, $dbPass, {'RaiseError' => 1});
			my $queryHandler = $dbHandler->prepare(qq/
				SELECT table_name AS tables 
				FROM information_schema.tables 
				WHERE table_schema = '$dbName'
			/);
			$queryHandler->execute();

			while (my $ref = $queryHandler->fetchrow_hashref()) {
				$tableHash{$ref->{'tables'}} = 1;
			}
			$queryHandler->finish();
		};
		if (my $ex = $@) {
			ConvoTreeEngine::Exception::Connectivity->throw(
				error   => $ex,
				service => 'mysql',
			);
		}
	}
	return $dbHandler;
}

sub closeConnection {
	my $class = shift;

	if (defined $dbHandler) {
		$dbHandler->disconnect();
		undef $dbHandler;
	}
}

1;