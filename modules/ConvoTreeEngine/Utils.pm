package ConvoTreeEngine::Utils;

{
	my %IGNORE_METHODS = map { $_ => 1 } qw(ISA);
	my %CLASS_LOADED;

	no strict 'refs';
	sub require {
		my ($invocant, $class, %opts) = @_;

		return if ($CLASS_LOADED{$class} && !$opts{force});

		no warnings 'once';
		eval "require $class";
		if (my $ex = $@) {
			if ("$ex" =~ m/you may need to install the $class module/) {
				if (%{"$class\::"} && grep { $_ !~ /::$/ && ! $IGNORE_METHODS{$_} } keys %{"$class\::"}) {
					$CLASS_LOADED{$class} = 1;
					return;
				}
			}
			die "$ex";
		}

		return $CLASS_LOADED{$class} = 1;
	}
}

1;