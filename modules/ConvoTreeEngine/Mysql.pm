package ConvoTreeEngine::Mysql;

use strict;
use warnings;

use DBI;

use ConvoTreeEngine::Config;

our $dbHandler;

sub getConnection {
	my $class = shift;

	if (!defined $dbHandler) {
		my $dbName = $ConvoTreeEngine::Config::dbName;
		my $dbHost = $ConvoTreeEngine::Config::dbHost;
		my $dbUser = $ConvoTreeEngine::Config::dbUser;
		my $dbPass = $ConvoTreeEngine::Config::dbPass;

		if (!$dbName || !$dbHost || !$dbUser || !$dbPass) {
			ConvoTreeEngine::Exception::Configuration->throw(
				error => 'The database connection is not configured',
			);
		}

		eval {
			$dbHandler = DBI->connect("DBI:mysql:database=" . $dbName . ";" . $dbHost, $dbUser, $dbPass, {'RaiseError' => 1});

			my $query = qq/
				SELECT table_name AS tables
				FROM information_schema.tables
				WHERE table_schema = ?;
			/;
			my $rows = $class->fetchRows($query, [$dbName]);

			my %tableHash;
			foreach my $row (@$rows) {
				$tableHash{$row->{'tables'}} = 1;
			}
			$class->createTables(%tableHash);
		};
		if (my $ex = $@) {
			ConvoTreeEngine::Exception::Connectivity->throw(
				error   => $ex,
				service => 'mysql',
				code    => 502,
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

sub fetchRows {
	my $class = shift;
	my $query = shift;
	my $bits  = shift || [];

	my $dbHandler = $class->getConnection;
	my $rows;
	$class->doQuery(sub {
		my $queryHandler = $dbHandler->prepare($query);
		$queryHandler->execute(@$bits);
		$rows = $queryHandler->fetchall_arrayref({});
		$queryHandler->finish();
	});

	return $rows;
}

sub insertForId {
	my $class = shift;
	my $query = shift;
	my $bits  = shift || [];

	my $dbHandler = $class->getConnection;
	my $id;
	$class->doQuery(sub {
		my $queryHandler = $dbHandler->prepare($query);
		$queryHandler->execute(@$bits);
		$queryHandler->finish();
		$id = $queryHandler->{mysql_insertid};
	});

	return $id;
}

sub doQuery {
	my $class = shift;
	my $code  = shift;

	my $query;
	if (!ref $code) {
		$query = $code;
		undef $code;
	}
	else {
		$query = shift;
	}
	my $bits = shift || [];

	eval {
		if ($code) {
			$code->();
		}
		else {
			my $queryHandler = $dbHandler->prepare($query);
			$queryHandler->execute(@$bits);
			$queryHandler->finish();
		}
	};
	if (my $ex = $@) {
		ConvoTreeEngine::Exception::SQL->throw(
			error => "$ex",
			sql   => $query,
			args  => $bits,
		);
	}

	return
}

sub createTables {
	my $class     = shift;
	my %tableHash = @_;

	my $dbHandler = $class->getConnection;

	$class->atomic(sub {
		unless ($tableHash{c_element_types}) {
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS c_element_types (
					type VARCHAR(15) PRIMARY KEY
				)
				ENGINE=InnoDB;
			/);

			$class->doQuery(qq/
				INSERT IGNORE INTO c_element_types (type) VALUES
					('item'),('note'),('raw'),('enter'),
					('exit'),('if'),('assess'),('varaible'),
					('choice'),('display'),('do'),('data');
			/);
		}

		unless ($tableHash{element}) {
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS element (
					id INT AUTO_INCREMENT PRIMARY KEY,
					type VARCHAR(15) NOT NULL,
					name VARCHAR(256),
					category VARCHAR(50),
					json JSON NOT NULL,
					UNIQUE element_name_category_index
						(name, category),
					FOREIGN KEY (type)
						REFERENCES c_element_types(type)
						ON DELETE RESTRICT
						ON UPDATE RESTRICT
				)
				ENGINE=InnoDB;
			/);

			$class->doQuery(qq/
				CREATE INDEX element_category_index
					USING BTREE
					ON element(category);
			/);
		}

		unless ($tableHash{element_series}) {
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS element_series (
					id INT AUTO_INCREMENT PRIMARY KEY,
					name VARCHAR(256) NOT NULL,
					category VARCHAR(50) NOT NULL,
					UNIQUE element_name_category_index
						(name, category)
				)
				ENGINE=InnoDB;
			/);

			$class->doQuery(qq/
				CREATE INDEX element_series_category_index
					USING BTREE
					ON element_series(category);
			/);
		}

		unless ($tableHash{series_to_element}) {
			$class->doQuery(qq/
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

			$class->doQuery(qq/
				CREATE INDEX series_to_element_series_id_index
					USING BTREE
					ON series_to_element(series_id);
			/);

			$class->doQuery(qq/
				CREATE INDEX series_to_element_element_id_index
					USING BTREE
					ON series_to_element(element_id);
			/);

			$class->doQuery(qq/
				CREATE INDEX series_to_element_nested_series_id_index
					USING BTREE
					ON series_to_element(nested_series_id);
			/);
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
		ConvoTreeEngine::Exception::Internal->throw(
			error => 'Unable to create a transaction lock',
			code  => 502,
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
		ConvoTreeEngine::Exception::Internal->throw(
			error => 'Unable to commit a transaction lock',
			code  => 502,
		);
	}

	return @response if wantarray;;
	return $response;
}

1;