package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my ($attrString, $bits) = $invocant->_parse_query_attrs($attrs);

	my $whereString;
	my @whereString;
	my @input;
	if ($args->{WHERE}) {
		$whereString = $args->{WHERE};
	}
	else {
		foreach my $field (keys $args) {
			my $ref = ref($args->{$field}) || '';
			if ($ref eq 'ARRAY') {
				my $string .= "$field IN (" . join(',', ('?') x @{$args->{$field}}) . ')';
				push @whereString, $string;
				push @input, @{$args->{$field}};
			}
			elsif ($ref eq 'HASH' && scalar(keys %{$args->{$field}}) == 1) {
				my ($key) = keys %{$args->{$field}};
				my $value = $args->{$field}{$key};
				push @whereString, "$field $key ?";
				push @input, $value;
			}
			else {
				push @whereString, "$field = ?";
				push @input, $args->{$field};
			}
		}
	}

	$whereString ||= join ' AND ', @whereString;
	$whereString = "WHERE $whereString" if $whereString;
	push @input, @$bits;
	my $query = qq/
		SELECT id, type, json FROM element
		$whereString
		$attrString
	/;
	my $rows = ConvoTreeEngine::Mysql::Connect->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	if (ref $args->{json}) {
		$args->{json} = JSON::encode_json($args->{json});
	}

	my $dbHandler = ConvoTreeEngine::Mysql::Connect->getConnection;
	my $queryHandler = $dbHandler->prepare(qq/
		INSERT INTO element (type, json) VALUES(?, ?);
	/);
	$queryHandler->execute($args->{type}, $args->{json});
	$queryHandler->finish();
	my $id = $queryHandler->{mysql_insertid};

	return $invocant->promote({
		id   => $id,
		type => $args->{type},
		json => $args->{json},
	});
}

sub asHashRef {
	my $self = shift;

	my $hash = JSON::decode_json($self->{json});
	$hash->{type} = $self->{type};
	$hash->{id}   = $self->{id};

	return $hash;
}

1;