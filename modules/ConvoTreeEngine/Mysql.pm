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
			if ($ex->isa('Exception::Class::Base')) {
				$ex->rethrow;
			}
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

	my $prefix = $ConvoTreeEngine::Config::tablePrefix;

	$class->atomic(sub {
		unless ($tableHash{"${prefix}c_element_types"}) {
			### A list of applicable element types, present just to restrict other things / typos from ending up in the mix
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS ${prefix}c_element_types (
					type VARCHAR(15) PRIMARY KEY,
					example JSON NOT NULL
				)
				ENGINE=InnoDB;
			/);

			require JSON;
			require ConvoTreeEngine::ElementExamples;
			my $query = qq/INSERT IGNORE INTO ${prefix}c_element_types (type, example) VALUES /;
			my @bits;
			foreach my $type (qw/item note raw enter exit if assess varaible choice display do data negate stop/) {
				my $example = $ConvoTreeEngine::ElementExamples::examples{$type};
				$example = JSON::encode_json($example);
				push @bits, $type, $example;
				$query .= '(?, ?),';
			}
			$query = substr $query, 0, -1;

			$class->doQuery($query, \@bits);
		}

		unless ($tableHash{"${prefix}element"}) {
			### The table containing elements
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS ${prefix}element (
					id INT AUTO_INCREMENT PRIMARY KEY,
					type VARCHAR(15) NOT NULL,
					name VARCHAR(256),
					category VARCHAR(50),
					json JSON NOT NULL,
					INDEX ${prefix}element_category_index
						(category) USING BTREE,
					UNIQUE ${prefix}element_name_category_index
						(name, category),
					FOREIGN KEY (type)
						REFERENCES ${prefix}c_element_types(type)
						ON DELETE RESTRICT
						ON UPDATE RESTRICT
				)
				ENGINE=InnoDB;
			/);
		}

		unless ($tableHash{"${prefix}element_series"}) {
			### The main data for a series
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS ${prefix}element_series (
					id INT AUTO_INCREMENT PRIMARY KEY,
					name VARCHAR(256) NOT NULL,
					category VARCHAR(50) NOT NULL,
					INDEX ${prefix}element_series_category_index
						(category) USING BTREE,
					UNIQUE ${prefix}element_name_category_index
						(name, category)
				)
				ENGINE=InnoDB;
			/);
		}

		unless ($tableHash{"${prefix}element_path"}) {
			### Certain element types have the ability to branch into different paths. This keeps track of those
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS ${prefix}element_path (
					id BIGINT AUTO_INCREMENT PRIMARY KEY,
					element_id INT NOT NULL,
					series_id INT NOT NULL,
					INDEX ${prefix}element_path_to_series_id_index
						(series_id) USING BTREE,
					INDEX ${prefix}element_path_to_element_id_index
						(element_id) USING BTREE,
					UNIQUE ${prefix}element_path_element_series_index
						(element_id, series_id),
					FOREIGN KEY (series_id)
						REFERENCES ${prefix}element_series(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE,
					FOREIGN KEY (element_id)
						REFERENCES ${prefix}element(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE
				)
				ENGINE=InnoDB;
			/);
		}

		unless ($tableHash{"${prefix}series_to_element"}) {
			### The data for the sequence of a series, as well as additional elements or series that are associated with the series
			$class->doQuery(qq/
				CREATE TABLE IF NOT EXISTS ${prefix}series_to_element (
					series_id INT NOT NULL,
					element_id INT,
					nested_series_id INT,
					sequence INT,
					INDEX ${prefix}series_to_element_series_id_index
						(series_id) USING BTREE,
					INDEX ${prefix}series_to_element_element_id_index
						(element_id) USING BTREE,
					INDEX ${prefix}series_to_element_nested_series_id_index
						(nested_series_id) USING BTREE,
					UNIQUE ${prefix}series_to_element_parts_index
						(series_id, element_id, nested_series_id),
					UNIQUE ${prefix}series_to_element_sequence_index
						(series_id, sequence),
					FOREIGN KEY (series_id)
						REFERENCES ${prefix}element_series(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE,
					FOREIGN KEY (element_id)
						REFERENCES ${prefix}element(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE,
					FOREIGN KEY (nested_series_id)
						REFERENCES ${prefix}element_series(id)
						ON DELETE CASCADE
						ON UPDATE CASCADE
				)
				ENGINE=InnoDB;
			/);
		}
	});

	return;
}

sub destroyTables {
	my $class = shift;

	my $prefix = $ConvoTreeEngine::Config::tablePrefix;

	$class->doQuery(qq/DROP TABLE IF EXISTS ${prefix}series_to_element;/);
	$class->doQuery(qq/DROP TABLE IF EXISTS ${prefix}element_path;/);
	$class->doQuery(qq/DROP TABLE IF EXISTS ${prefix}element_series;/);
	$class->doQuery(qq/DROP TABLE IF EXISTS ${prefix}element;/);
	$class->doQuery(qq/DROP TABLE IF EXISTS ${prefix}c_element_types;/);

	return;
}

sub atomic {
	my $class = shift;
	my $code  = shift;

	my $dbHandler = $class->getConnection;
	my $autoCommit = $dbHandler->{AutoCommit};
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

	if ($autoCommit) {
		$dbHandler->{AutoCommit} = $autoCommit; ### Setting to one automatically commits
		unless ($dbHandler->{AutoCommit}) {
			$dbHandler->rollback;
			ConvoTreeEngine::Exception::Internal->throw(
				error => 'Unable to commit a transaction lock',
				code  => 502,
			);
		}
	}

	return @response if wantarray;;
	return $response;
}

1;