package ConvoTreeEngine::Object;

use strict;
use warnings;

use ConvoTreeEngine::Utils;
use ConvoTreeEngine::Config;
use ConvoTreeEngine::Mysql;

sub _table {
	my $self  = shift;
	my $table = shift;
	return $ConvoTreeEngine::Config::tablePrefix . $table;
}

sub _prep_args {
	my $self = shift;

	return {} unless @_;

	return $_[0] if (ref($_[0]) || '') eq 'HASH';

	ConvoTreeEngine::Exception::Internal->throw(
		error => "odd number of parameters cannot be cast as hash",
	) if @_ % 2;

	for (my $i = 0; $i < @_; $i += 2) {
		ConvoTreeEngine::Exception::Internal->throw(
			error => "has keys must be defined",
		) unless defined $_[$i];
	}

	return {@_};
}

sub _prep_args_multi {
	my $self  = shift;
	my $count = shift;

	return {} unless @_;

	my @response;
	while (@_ && (ref($_[0]) || '') eq 'HASH') {
		push @response, shift;
	}

	if (@_) {
		push @response, $self->_prep_args(@_);
	}

	while (@response < $count) {
		push @response, {};
	}

	return @response;
}

{
	my %describes;
	my %primary_keys;
	sub _describe {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $describes{$table} ||= do {
			my $describe = { map {$_->{Field} => $_} @{ $invocant->_mysql->fetchRows(qq/DESCRIBE $table;/) } };

			my @primary;
			foreach my $field (sort keys %$describe) {
				if (($describe->{$field}{Key} || '') eq 'PRI') {
					push @primary, $field;
				}
			}
			if (@primary) {
				$primary_keys{$table} = \@primary;
			}

			$describe;
		};
	}

	sub _primary_keys {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $primary_keys{$table} || do {
			$invocant->_describe();
			$primary_keys{$table};
		};

	}
}

sub createAccessors {
	my $class  = shift;
	my @fields = @_;

	foreach my $field (@fields) {
		my $symbol_name = "${class}::$field";
		no strict 'refs';
		next if defined *{$symbol_name};
		*{$symbol_name} = sub {
			return shift->{$field};
		};
	}

	return;
}

=head2 createRelationships

Creaete a relationship between the calling class and another class

Expects an array of hashrefs with the following keys:

* name     - The name of the method
* class    - The other class that we're relating to
* fields   - A hashref where the keys are the names of args that would be passed into the other
             method's 'search' class and the values are either methods on the calling class, or
             code refs that expect the calling object to be passed in as the only argument.
             Alternately, instead of a hashref, if only comparing a single field, and the name
             is the same on both ends, you can just use that name.
* order_by - Optional; a default order to use if no others are specified
* many     - Optional, boolean; If present and true, call 'search', otherwise call 'find'

=cut

sub createRelationships {
	my $class         = shift;
	my @relationships = shift;

	foreach my $rel (@relationships) {
		my $symbol_name = "${class}::$rel->{name}";
		no strict 'refs';
		next if defined *{$symbol_name};
		my $otherClass = $rel->{class};
		ConvoTreeEngine::Utils->require($otherClass);

		$rel->{fields} = {$rel->{fields} => $rel->{fields}} unless ref $rel->{fields};

		my $mutate = '__' . $rel->{name} . '_mutateArgs';
		*{"${class}::$mutate"} = sub {
			my $self = shift;
			my $args = shift;

			foreach my $otherField (keys %{$rel->{fields}}) {
				my $selfMethod = $rel->{fields}{$otherField};
				my $value;
				if ((ref $selfMethod || '') eq 'CODE') {
					$value = $selfMethod->($self);
				}
				else {
					$value = $self->$selfMethod();
				}
				$args->{$otherField} = $value;
			}

			return $args;
		};
		if ($rel->{many}) {
			*{$symbol_name} = sub {
				my $self = shift;
				my ($args, $attrs) = $class->_prep_args_multi(2, @_);

				$args = $self->$mutate($args);
				$attrs->{order_by} ||= $rel->{order_by};

				return $otherClass->search($args, $attrs);
			};
		}
		else {
			*{$symbol_name} = sub {
				my $self = shift;
				my $args = $class->_prep_args(@_);

				$args = $self->$mutate($args);

				return $otherClass->find($args);
			};
		}
	}
}

sub create {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	my $self = $class->promote({});

	my $describe = $class->_describe;

	my $table = $class->_table;
	my (@fields, @values);
	foreach my $field (sort keys %$describe) {
		if (exists $args->{$field}) {
			push @fields, $field;
			if ($args->{$field} && ref $args->{$field} && $describe->{$field}{Type} eq 'json') {
				$args->{$field} = JSON::encode_json($args->{$field});
			}
			push @values, $args->{$field};
			$self->{$field} = delete $args->{$field};
		}
	}
	if (keys %$args) {
		ConvoTreeEngine::Exception::Input->throw(
			error => "Table '$table' does not have column(s) [" . join(', ', sort(keys %$args)) . ']',
		);
	}

	my $questionmarks = join ',', ('?') x @fields;
	my $fields = join ',', @fields;

	if ($describe->{id} && ($describe->{id}{Key} || '') eq 'PRI') {
		my $id = $class->_mysql->insertForId(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);

		$self->{id} = $id;
	}
	else {
		$class->_mysql->doQuery(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);
	}

	return $self;
}

sub _parse_query_attrs {
	my $self  = shift;
	my $attrs = shift;

	my @string;

	if (defined $attrs->{group_by}) {
		### I cannot think of a scenario where we would use this in a search, but including it anyway.
		$attrs->{group_by} = [$attrs->{group_by}] unless ref($attrs->{group_by} || '') eq 'ARRAY';
		my $string = 'GROUP BY ' . join(',', @{$attrs->{group_by}});
		push @string, $string;
		if (defined $attrs->{having}) {
			push @string, 'HAVING ' . delete $attrs->{having};
		}
	}

	if (defined $attrs->{order_by}) {
		$attrs->{order_by} = [$attrs->{order_by}] unless ref($attrs->{order_by} || '') eq 'ARRAY';
		my $string = 'ORDER BY ' . join(',', @{$attrs->{order_by}});
		push @string, $string;
	}
	if (defined $attrs->{limit}) {
		push @string, 'LIMIT ' . $attrs->{limit};
	}
	if (defined $attrs->{offset}) {
		push @string, 'OFFSET ' . $attrs->{offset};
	}

	return join(' ', @string) || '';
}

sub _parse_where_args {
	my $invocant     = shift;
	my $whereString  = shift;
	my $input        = shift;
	my $fieldDetails = shift;
	my $args         = shift;

	my $ref = ref($args) || '';

	if ($ref eq 'ARRAY') {
		foreach my $argPart (@$args) {
			my @nestedWhereString;
			$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, $argPart);
			next unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				my $string = '(' . join(' AND ', @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		return;
	}
	return unless $ref eq 'HASH';

	### We're going to mutate args, so do a shallow clone of them
	$args = {map {$_ => $args->{$_}} keys %$args};
	delete @{$args}{qw/WHERE JOIN/};

	my $table = $invocant->_table;
	foreach my $field (keys %$args) {
		next if $field eq 'OR' || $field eq 'AND';
		if ($fieldDetails->{$field} && $field !~ m/\./) {
			$args->{"$table.$field"} = delete $args->{$field};
		}
	}

	FIELD:
	foreach my $field (keys %$args) {
		my $ref = ref($args->{$field}) || '';
		if ($field eq 'OR' || $field eq 'AND') {
			my @nestedWhereString;
			$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, $args->{$field});
			next FIELD unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				my $string = '(' . join(" $field ", @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		elsif ($ref eq 'ARRAY') {
			my $string = "$field IN (";
			my $hasUndef = 0;
			my $count = 0;
			my @complex;
			foreach my $value (@{$args->{$field}}) {
				if (!defined $value) {
					$hasUndef = 1;
				}
				elsif (ref $value) {
					push @complex, $value;
				}
				else {
					$count++;
					push @$input, $value;
				}
			}

			my @nestedWhereString;
			if ($hasUndef) {
				push @nestedWhereString, "$field IS NULL";
			}
			if ($count) {
				if ($count == 1) {
					push @nestedWhereString, "$field = ?";
				}
				else {
					my $string= "$field IN (" . join(',', ('?') x $count) . ')';
					push @nestedWhereString, $string;
				}
			}
			if (@complex) {
				foreach my $value (@complex) {
					$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, {$field => $value});
				}
			}

			next FIELD unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				my $string = '(' . join(" OR ", @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		elsif ($ref eq 'HASH') {
			HASH_KEY:
			foreach my $key (keys %{$args->{$field}}) {
				### Allowing multiple keys is useful if we want to search for greater than one value and less than another
				my $value = $args->{$field}{$key};
				if (!defined $value) {
					$key = 'IS' if $key eq '=';
					$key = 'IS NOT' if $key eq '!=';
					push @$whereString, "$field $key NULL";
				}
				elsif ((ref $value || '') eq 'ARRAY') {
					if ($key eq 'OR' || $key eq 'AND') {
						my @nestedWhereString;
						foreach my $val (@$value) {
							$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, {$field => $val});
						}
						next HASH_KEY unless @nestedWhereString;
						if (@nestedWhereString == 1) {
							push @$whereString, $nestedWhereString[0];
						}
						else {
							my $string = '(' . join(" $key ", @nestedWhereString) . ')';
							push @$whereString, $string;
						}
					}
					else {
						### Useful for the 'LIKE' operator
						foreach my $val (@$value) {
							if (!defined $val) {
								$key = 'IS' if $key eq '=';
								$key = 'IS NOT' if $key eq '!=';
								push @$whereString, "$field $key NULL";
							}
							else {
								push @$whereString, "$field $key ?";
								push @$input, $val;
							}
						}
					}
				}
				else {
					push @$whereString, "$field $key ?";
					push @$input, $value;
				}
			}
		}
		elsif ($ref eq 'SCALAR') {
			push @$whereString, "$field ${$args->{$field}}";
		}
		else {
			if (defined $args->{$field}) {
				push @$whereString, "$field = ?";
				push @$input, $args->{$field};
			}
			else {
				push @$whereString, "$field IS NULL";
			}
		}
	}

	return;
}

=head2 search

Compose a query string, Make the query, return the results.

Expects two arguments, $args and $attrs. See `_parse_query_attrs` for explanation of attrs

$args can contain the following special arguments:

* WHERE - A text string containing a SQL "WHERE" clause (not begining with the word "WHERE",
          but everything that comes after that).
* JOIN  - A text string containing one or more SQL "JOIN" clauses (beginning with the
          appropriate "JOIN", "LEFT JOIN", etc keywords).

The following patterns can be used:

* {field => $value}
    * Translates to the string "field = $value" (or "field IS NULL" if the value is undef)
    * The value will be appropriately quoted

* {field => [$value1, $value2, $value3]}
    * Translates to the string "field IN ($value1, $value2, $value3)"
    * If one of the values is undef, instead translates to "(field IS NULL OR field IN
      ($value1, $value3))"
    * The values will be appropriately quoted

* {field => [$value1, $value2, {$operator => $value3}]}
    * Example: {field => [1, 3, {'>' => 7}]}
    * The example would translate to the string "(field IN (1, 3) OR field > 7)"

* {field => {$operator => $value}}
    * Example: {count => {'>' => 1}}
    * The example would translate to the string "field > 1"
    * If the operator is "=" or "!=" and the value is undef, translates to "field IS NULL"
      or "filed IS NOT NULL"
    * The value will be appropriately quoted

* {$field => {$operator1 => $value1, $operator2 => $value2}}
    * Translates to something similar to "field $operator1 $value1 AND field $operator2 $value2"
    * Useful for generating a string like "field > 1 AND field < 3"
    * See above for other details

* {field => {$operator => [$value1, $value2]}}
    * Translates to a string similar to "field $operator $value1 AND field $operator $value2"
    * Useful for the "LIKE" operator
    * See above for other details

* {field => \$value}
    * Translates to the string "field $value"
    * Presumably $value contains an operator and a value. If so, that falue will need to have been appropriately quoted in the string

* {OR => {field1 => $value1, field2 => $value2}}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field1 = $value1 OR field2 = $value2)"

* {OR => [{field => $value1}, {field => $value2}]}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field = $value1 OR field = $value2)"

* {field => {OR => [$value1, $value2]}}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field = $value1 OR field = $value2)"

* {field => {OR => [{$operator => $value1}, {$operator => $value2}]}}
    * Both "AND" and "OR" are supported
    * Example: {field => {OR => [{'>' => 1}, {'<' => 5}]}}
    * The example would translate to the string "(field > 1 OR field < 5)"

=cut

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $attrString = $invocant->_parse_query_attrs($attrs);
	my $describe = $invocant->_describe;

	my $table = $invocant->_table;

	my $joinString = '';
	if ($args->{JOIN}) {
		$joinString = $args->{JOIN};
	}

	my $whereString;
	my @whereString;
	push @whereString, $args->{WHERE} if $args->{WHERE};
	my @input;

	$invocant->_parse_where_args(\@whereString, \@input, $describe, $args);

	$whereString = join ' AND ', @whereString;
	$whereString = "WHERE $whereString" if $whereString;

	my $fields = "$table." . join(", $table.", keys(%$describe));
	my $query = qq/
		SELECT $fields FROM $table
		$joinString
		$whereString
		$attrString
	/;
	my $rows = $invocant->_mysql->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

sub find {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);
	my @result = $invocant->search($args, $attrs);

	if (@result > 1) {
		ConvoTreeEngine::Exception::DuplicateRecord->throw(
			args => $args,
		);
	}

	return $result[0];
}

sub findOrDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	return $result if $result;
	ConvoTreeEngine::Exception::RecordNotFound->throw(
		args => $args,
	);
}

sub findAndDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	ConvoTreeEngine::Exception::DuplicateRecord->throw(
		args => $args,
	) if $result;

	return;
}

sub _primary_key_where_clause {
	my $invocant = shift;

	my $table = $invocant->_table;
	my $primary_keys = $invocant->_primary_keys;
	die "Table '$table' does not have primary keys" unless $primary_keys && @$primary_keys;

	my @where;
	my @bits;
	foreach my $key (@$primary_keys) {
		push @where, "$key = ?";
		push @bits, $invocant->{$key};
	}
	my $where = join ' AND ', @where;

	return ($where, \@bits);
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my @ro = $self->_read_only_fields;
	foreach my $field (@ro) {
		if (exists $args->{$field}) {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$field' field cannot be updated on the '" . ref $self . "' object",
				args  => $args,
			) if (defined $args->{$field} xor defined $self->$field()) || (defined $args->{$field} && $args->{$field} ne $self->$field());
		}
	}

	my $describe = $self->_describe;

	my @sets;
	my @bits;
	foreach my $arg (keys %$args) {
		if ($describe->{$arg}) {
			push @sets, "$arg = ?";
			if ($args->{$arg} && ref $args->{$arg} && $describe->{$arg}{Type} eq 'json') {
				$args->{$arg} = JSON::encode_json($args->{$arg});
			}
			push @bits, $args->{$arg};
		}
		else {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$arg' field does not exist on the '" . ref $self . "' object",
				args  => $args,
			);
		}
	}
	my $sets = join ', ', @sets;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;
	push @bits, @$pk_bits;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/UPDATE $table SET $sets WHERE $where;/,
		\@bits,
	);

	return $self->refresh;
}

sub delete {
	my $self = shift;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/DELETE FROM $table WHERE $where;/,
		$pk_bits,
	);

	return;
}

sub refresh {
	my $self = shift;

	my $table    = $self->_table;
	my $describe = $self->_describe;
	my $fields   = join ', ', keys(%$describe);
	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $query = qq/SELECT $fields FROM $table WHERE $where;/;
	my $rows = $self->_mysql->fetchRows($query, $pk_bits);
	if (@$rows) {
		my $found = $rows->[0];
		%$self = %$found;
	}

	return $self;
}

sub all {
	my $invocant = shift;
	my @results = $invocant->search({}, {});

	return @results;
}

sub promote {
	my $invocant = $_[0];
	my $class = ref($invocant) || $invocant;

	my $new = bless $_[1], $class;
	$_[1] = $new;
	return $_[1];
}

sub asHashRef {
	my $self = shift;
	my $describe = $self->_describe();

	my $hash = {};
	foreach my $field (keys %$describe) {
		my $val = $self->{$field};
		if ($val && $describe->{$field}{Type} eq 'json') {
			$hash->{$field} = JSON::decode_json($val);
		}
		else {
			$hash->{$field} = $val;
		}
	}

	return $hash;
}

sub atomic {
	my $invocant = shift;
	return $invocant->_mysql->atomic(@_);
}

sub _mysql {
	return 'ConvoTreeEngine::Mysql';
}

1;