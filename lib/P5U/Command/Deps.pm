package P5U::Command::Deps;

use 5.010;
use strict;
use utf8;
use P5U-command;

BEGIN {
	$P5U::Command::Deps::AUTHORITY = 'cpan:TOBYINK';
	$P5U::Command::Deps::VERSION   = '0.001';
}

use constant abstract      => q  <scan Perl source code for dependencies>;
use constant command_names => qw <deps dependencies scandeps>;
use constant usage_desc    => q  <%c deps %o FILE(s)?>;

sub opt_spec
{
	return (
		[ 'format|f=s'   => 'output format (text, mi, pretdsl)' ],
		[ 'skipcore|c'   => 'skip core modules' ],
	);
}

sub execute
{
	my ($self, $opt, $args) = @_;
	
	require Path::Class::Rule;
	require Path::Class::File;
	require Path::Class::Dir;
	
	my @files = map {
		-d $_
			? "Path::Class::Rule"->new->perl_file->all($_)
			: "Path::Class::File"->new($_)
	} @$args;
	@files = "Path::Class::Rule"->new->perl_file->all unless @$args;
	
	my $deps = $self->_get_deps(@files);
	$self->_whittle($deps) if exists $opt->{skipcore};
	print $self->_output($deps, $opt->{format});
}

sub _get_deps
{
	my ($self, @files) = @_;
	
	require CPAN::Meta::Requirements;
	
	my ($BUILD, $TEST, $XTEST, $RUNTIME) = map {
		"CPAN::Meta::Requirements"->new;
	} 1..4;
	
	require Perl::PrereqScanner;
	my $scan = "Perl::PrereqScanner"->new;
	
	for my $_ (@files)
	{
		my $R
			= /.PL$/        ? $BUILD
			: /\bxt\b.+\.t/ ? $XTEST
			: /\.t/         ? $TEST
			:                 $RUNTIME;
		$R->add_requirements( $scan->scan_file("$_") );
	}
	
	+{
		BUILD    => $BUILD,
		TEST     => $TEST,
		XTEST    => $XTEST,
		RUNTIME  => $RUNTIME,
	};
}

sub _whittle
{
	my ($self, $deps, $perlver) = @_;
	
	require Module::CoreList;
	
	$perlver //= 0 + $deps->{RUNTIME}->as_string_hash->{perl};
	$self->usage_error("no Perl version listed, so cannot --skipcore")
		unless $Module::CoreList::version{$perlver};
	my $core = bless $Module::CoreList::version{$perlver}, 'Module::CoreList';
	
	for my $d (values %$deps)
	{
		for my $module ($d->required_modules)
		{
			# whittle magic Module::Install stuff
			if ($module =~ /^inc::Module::/)
			{
				$d->clear_requirement($module);
			}
			
			# skip modules never in core, or ever removed from core
			next unless $core->first_release($module);
			next if     $core->removed_from($module);
			
			# whittle modules if the core version meets requirement
			if ($d->accepts_module($module, $core->{$module}))
			{
				$d->clear_requirement($module);
			}
		}
	}
}

sub _output
{
	my ($self, $deps, $format) = @_;
	$format =~ /pret/i and return $self->_output_pretdsl($deps);
	$format =~ /mi/i   and return $self->_output_mi($deps);
	
	for my $key (sort keys %$deps)
	{
		next unless $deps->{$key}->required_modules;
		print "# $key\n";
		for my $mod (sort $deps->{$key}->required_modules)
		{
			printf "%s %s\n", $mod, $deps->{$key}->requirements_for_module($mod);
		}
	}
}

my %term = (
	TEST    => 'test_requires',
	BUILD   => 'configure_requires',
	RUNTIME => 'requires',
);

sub _output_pretdsl
{
	my ($self, $deps) = @_;
	
	print "[\n";
	for my $key (sort keys %$deps)
	{
		next unless exists $term{$key};
		for my $mod (sort $deps->{$key}->required_modules)
		{
			next if $mod eq 'perl';
			printf
				"\t%s p`%s %s`;\n",
				$term{$key},
				$mod,
				$deps->{$key}->requirements_for_module($mod),
			;
		}
	}
	print "].\n";
}

sub _output_mi
{
	my ($self, $deps) = @_;
	
	for my $key (sort keys %$deps)
	{
		next unless exists $term{$key};
		for my $mod (sort $deps->{$key}->required_modules)
		{
			next if $mod eq 'perl';
			printf
				"%s \"%s\" => %s;\n",
				$term{$key},
				$mod,
				$deps->{$key}->requirements_for_module($mod),
			;
		}
	}
}

1;

__END__

=head1 NAME

P5U::Command::Deps - p5u plugin to scan a file or directory for Perl dependencies

=head1 SYNOPSIS

 $ p5u deps lib/Foo/Bar.pm
 # RUNTIME
 Foo 1.000
 constant 0
 perl 5.010
 strict 0
 utf8 0

 $ p5u deps --skipcore lib/Foo/Bar.pm
 # RUNTIME
 Foo 1.000

=head1 DESCRIPTION

Given a list of filenames and/or directories, uses L<Perl::PrereqScanner>
to calculate a combined list of dependencies. If no filenames are given,
then the current directory is assumed.

It uses file naming conventions to attempt to classify dependencies as
"runtime", "test" and "build".

With the C<< --skipcore >> option, will skip dependencies that are satisfied
by Perl core. This requires at least one C<< use VERSION >> line in the files
being scanned.

Output is in the text format shown above, but with C<< --format=mi >>
will attempt to output L<Module::Install>-style requirements. With
C<< --format=pretdsl >> will output data in a format suitable for
L<RDF::TrineX::Parser::Pretdsl>.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=P5U-Command-Deps>.

=head1 SEE ALSO

L<P5U>.

L<Perl::PrereqScanner>,
L<App::PrereqGrapher>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

