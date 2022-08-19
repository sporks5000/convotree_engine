package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

sub _table {
	return 'element';
}

#=====================#
#== Field Accessors ==#
#=====================#

sub id {
	return shift->{id};
}

sub type {
	return shift->{type};
}

sub json {
	return shift->{json};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	if (ref $args->{json}) {
		$args->{json} = JSON::encode_json($args->{json});
	}

	my $table = $invocant->_table;
	my $id = ConvoTreeEngine::Mysql->insertForId(
		qq/INSERT INTO $table (type, json) VALUES(?, ?);/,
		[$args->{type}, $args->{json}],
	);

	return $invocant->promote({
		id   => $id,
		type => $args->{type},
		json => $args->{json},
	});
}

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
	my $table = $invocant->_table;
	my $query = qq/
		SELECT id, type, json FROM $table
		$whereString
		$attrString
	/;
	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	ConvoTreeEngine::Exception::Input->throw(
		error => "Only the 'json' field can be updated on the 'Element' object",
		args  => $args,
	) if !$args->{json} || scalar(keys %$args) > 1;

	if (ref $args->{json}) {
		$args->{json} = JSON::encode_json($args->{json});
	}

	my $table = $self->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/UPDATE $table SET json = ? WHERE id = ?;/,
		[$args->{json}, $self->id],
	);

	return $self->refresh;
}

sub delete {
	my $self = shift;

	my $table = $self->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/DELETE FROM $table WHERE id = ?;/,
		[$self->id],
	);

	return;
}

#===========================#
#== Returning Information ==#
#===========================#

sub jsonRef {
	return JSON::decode_json(shift->json);
}

sub asHashRef {
	my $self = shift;

	my $hash = $self->jsonRef;
	$hash->{type} = $self->type;
	$hash->{id}   = $self->id;

	return $hash;
}

1;