package ConvoTreeEngine::Mysql::Connect;

use strict;
use warnings;

use DBI;

use ConvoTreeEngine::Config;

our $dbHandler;

my $dbName = $ConvoTreeEngine::Config::dbName;
my $dbHost = $ConvoTreeEngine::Config::dbHost;
my $dbUser = $ConvoTreeEngine::Config::dbUser;
my $dbPass = $ConvoTreeEngine::Config::dbPass;

sub getConnection {
	my $class = shift;

	if (!defined $dbHandler) {
		if (!$dbName || !$dbHost || !$dbUser || !$dbPass) {
			ConvoTreeEngine::Exception::Configuration->throw(
				error => 'The database connection is not configured',
			);
		}

		eval {
			$dbHandler = DBI->connect("DBI:mysql:database=" . $dbName . ";" . $dbHost, $dbUser, $dbPass, {'RaiseError' => 1});
			my $queryHandler = $dbHandler->prepare(qq/
				SELECT table_name AS tables 
				FROM information_schema.tables 
				WHERE table_schema = '$dbName'
			/);
			$queryHandler->execute();

			my %tableHash;
			while (my $ref = $queryHandler->fetchrow_hashref()) {
				$tableHash{$ref->{'tables'}} = 1;
			}
			$queryHandler->finish();
			$class->createTables($dbHandler, %tableHash);
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

sub createTables {
	my $class     = shift;
	my $dbHandler = shift;
	my %tableHash = @_;

	$class->atomic(sub {
		unless ($tableHash{c_element_types}) {
			my $queryHandler = $dbHandler->prepare(qq/
				CREATE TABLE IF NOT EXISTS c_element_types (
					type VARCHAR(15) PRIMARY KEY
				)
				ENGINE=InnoDB;
			/);
			$queryHandler->execute();
			$queryHandler->finish();

			$queryHandler = $dbHandler->prepare(qq/
				INSERT INTO c_element_types (type) VALUES
					('item'),('raw'),('enter'),('exit'),
					('if'),('assess'),('varaible'),('choice'),
					('display'),('do'),('data');
			/);
			$queryHandler->execute();
			$queryHandler->finish();
		}

		unless ($tableHash{element}) {
			my $queryHandler = $dbHandler->prepare(qq/
				CREATE TABLE IF NOT EXISTS element (
					id INT AUTO_INCREMENT PRIMARY KEY,
					type VARCHAR(15) NOT NULL,
					json JSON NOT NULL,
					FOREIGN KEY (type)
						REFERENCES c_element_types(type)
						ON DELETE RESTRICT
						ON UPDATE RESTRICT
				)
				ENGINE=InnoDB;
			/);
			$queryHandler->execute();
			$queryHandler->finish();
		}

		unless ($tableHash{element_series}) {
			my $queryHandler = $dbHandler->prepare(qq/
				CREATE TABLE IF NOT EXISTS element_series (
					id INT AUTO_INCREMENT PRIMARY KEY,
					name VARCHAR(256) UNIQUE NOT NULL
				)
				ENGINE=InnoDB;
			/);
			$queryHandler->execute();
			$queryHandler->finish();
		}

		unless ($tableHash{series_to_element}) {
			my $queryHandler = $dbHandler->prepare(qq/
				CREATE TABLE IF NOT EXISTS series_to_element (
					series_id INT NOT NULL,
					element_id INT,
					nested_series_id INT,
					sequence INT,
					PRIMARY KEY (
						series_id,
						element_id,
						nested_series_id,
						sequence
					),
					FOREIGN KEY (series_id)
						REFERENCES element_series(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE,
					FOREIGN KEY (element_id)
						REFERENCES element(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE,
					FOREIGN KEY (nested_series_id)
						REFERENCES element_series(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE
				)
				ENGINE=InnoDB;
			/);
			$queryHandler->execute();
			$queryHandler->finish();

			$queryHandler = $dbHandler->prepare(qq/
				CREATE INDEX series_to_element_series_id_index
					USING BTREE
					ON series_to_element(series_id);
			/);
			$queryHandler->execute();
			$queryHandler->finish();

			$queryHandler = $dbHandler->prepare(qq/
				CREATE INDEX series_to_element_element_id_index
					USING BTREE
					ON series_to_element(element_id);
			/);
			$queryHandler->execute();
			$queryHandler->finish();

			$queryHandler = $dbHandler->prepare(qq/
				CREATE INDEX series_to_element_nested_series_id_index
					USING BTREE
					ON series_to_element(nested_series_id);
			/);
			$queryHandler->execute();
			$queryHandler->finish();
		}
	});

	return;
}

sub atomic {
	my $class = shift;
	my $code  = shift;

	my $dbHandler = $class->getConnection;
	$dbHandler->{AutoCommit} = 0;
	if ($dbHandler->{AutoCommit}) {
		ConvoTreeEngine::Exception::Unexpected->throw(
			error => 'Unable to create a transaction lock',
		);
	}

	my $response;
	my @response;
	eval {
		if (wantarray) {
			@response = $code->();
		}
		else {
			$response = $code->();
		}
	};
	if (my $ex = $@) {
		ConvoTreeEngine::Exception::Unexpected->promote($ex);
		$dbHandler->rollback;
		$ex->rethrow;
	}

	$dbHandler->{AutoCommit} = 1; ### Setting to one automatically commits
	unless ($dbHandler->{AutoCommit}) {
		$dbHandler->rollback;
		ConvoTreeEngine::Exception::Unexpected->throw(
			error => 'Unable to commit a transaction lock',
		);
	}

	return @response if wantarray;;
	return $response;
}

1;