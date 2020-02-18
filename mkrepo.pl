#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Mon Feb 17 17:49:53 2020
# Last Modified By: Johan Vromans
# Last Modified On: Tue Feb 18 12:39:45 2020
# Update Count    : 176
# Status          : Unknown, Use with caution!

# Based on code written by Peter Watkins.
# Copyright (c) 2008-2010 Peter Watkins. All Rights Reserved.
# Licensed under terms of the GNU General Public License

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'LMS Plugin tools';
# Program name and version.
my ($my_name, $my_version) = qw( mkrepo 0.001 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $profile = "test";
my $title;
my $repodir;
my $repobase;
my $verbose = 1;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace   |= ($debug || $test);
$verbose |= $trace;

################ Configuration ################

# Global config. Items can be overridden by the selected profile.

my %config =
  ( creator => 'Johan Vromans',

    # Creator's email address.
    emailAddress => 'jvromans@squirrel.nl',

    # Default language (for HTML).
    defaultLang => 'EN',

    # Repo description.
    repoTitle => $title || "Johan's LMS plugins",

    # Where we look for zip files.
    localWebDir => $repodir || 'dist',

    # Will change ${'localWebDir'}/$somepath to ${'urlBase'}/$somepath
    # for <url> URLs in the repo XML
    urlBase => $repobase || 'https://www.squirrel.nl/lms',

    # Look here for ${pluginName}.html info file.
    # Uncomment or leave empty to use localWebDir.
    # infoUrlSource => '',

    # Will change $infoUrlSource/somepath to $infoUrlBase/somepath
    # for <link> URLs in the repo XML
    # Uncomment or leave empty to use urlBase.
    # infoUrlBase => '',

    # Prepend to version in zip name (my zip files have names
    # like MyApp-7a1.zip while install.xml has version 0.7a1; the
    # version in the repo XML should match install.xml)
    versionPrefix => '',

    # End of config values.
  );

$config{infoUrlSource} ||= $config{localWebDir};
$config{infoUrlBase}   ||= $config{urlBase};

# Define two profiles: 'test' and 'live'.

my %profiles =
  (
   live =>
   { files   =>	{ xml  => $config{localWebDir}."/repodata.xml",
		  html => $config{localWebDir}."/repodata.html" },
     # exclude files under directories whose name ends in "-test"
     excludeRegexp => undef,
   },
   test =>
   { files   =>	{ xml  => $config{localWebDir}."/repodata-test.xml",
		  html => $config{localWebDir}."/repodata-test.html" },
     excludeRegexp => undef,
     repoTitle => "LMS extensions (TEST collection)",
   },
);


################ Presets ################

################ The Process ################

use File::Spec::Functions qw(:ALL);
use File::Basename;
use File::Path;
use XML::Simple;
use Digest::SHA1;
use File::Find;
use Archive::Zip qw( :ERROR_CODES );

# Subroutine forwards.
sub escapeHTML($);
sub unescapeBR($);
sub getMTimeString($);
sub makeElements($$);
sub getStrings($$$$$);
sub getHash($);
sub getURL($);
sub getBasename($);
sub getMtime($);
sub findZips($$);
sub getTargetInfo($);
sub dumper($);

my %latestZips;
my %latestMinVersionZips;
my %mtimes;
my %tempdirs;

my $profileName = $ARGV[0] || $profile;
unless ( exists( $profiles{$profileName} ) ) {
    die( "Profile \"$profileName\" does not exist.\n",
	 "Available profiles: ", join(" ", sort(keys(%profiles))), "\n" );
}
# Copy profile data into config.
my %chosenProfile = %{$profiles{$profileName}};
while ( my ($k,$v) = each(%chosenProfile) ) {
    $config{$k} = $v;
}

# Find all zips.
my @allzips = findZips( $config{localWebDir}, $config{excludeRegexp} );
warn("Number of plugin zips found = ", scalar(@allzips), "\n") if $verbose;

# Figure out what's the latest for each plugin.
foreach my $zipinfo ( @allzips ) {

    my $base      = $zipinfo->{basename};
    my $thismtime = $zipinfo->{mtime};

    # For this plugin.
    if ( defined($base) && (!defined($latestZips{$base})) ) {
	$mtimes{$base} = getMTimeString($thismtime);
	$latestZips{$base} = $zipinfo;
    }
    else {
	my $oldmtime = getMtime($latestZips{$base}->{fullpath});
	if ( $thismtime > $oldmtime ) {
	    $latestZips{$base} = $zipinfo;
	    $mtimes{$base} = getMTimeString($thismtime);
	}
    }
    # For this plugin at this minVersion.
    my $minv = $zipinfo->{minVersion};
    if ( defined($base.$minv) && (!defined($latestMinVersionZips{$base.$minv})) ) {
	$mtimes{$base.$minv} = getMTimeString($thismtime);
	$latestMinVersionZips{$base.$minv} = $zipinfo;
    }
    else {
	my $oldmtime = getMtime($latestMinVersionZips{$base.$minv}->{fullpath});
	if ( $thismtime > $oldmtime ) {
	    $latestMinVersionZips{$base.$minv} = $zipinfo;
	    $mtimes{$base.$minv} = getMTimeString($thismtime);
	}
    }
}

my %data = ( html => '', xml => '' );

# Producing the HTML.
foreach my $a ( sort {lc $a cmp lc $b} keys(%latestZips) ) {

    my $app = $latestZips{$a};
    my $base = $app->{basename};
    my $titleStrings = $app->{strings}->{'PLUGIN_'.uc($base)};
    my $descStrings = $app->{strings}->{'PLUGIN_'.uc($base).'_DESC'};

    # Grab the simple description for the HTML.
    my $simpleDesc = $descStrings->{$config{defaultLang}};

    # HTML.
    if ( my $infourl = $app->{infoUrl} ) {
	$data{html} .= "<p><a href=\"".escapeHTML($infourl)."\">".
	  escapeHTML($titleStrings->{$config{defaultLang}})."</a><br/>\n";
    }
    else {
	$data{html} .= '<p>'.escapeHTML($titleStrings->{$config{defaultLang}})."<br/>\n";
    }
    $data{html} .= "v" . $app->{version};
    $data{html} .= ", " . getMTimeString($app->{mtime});
    $data{html} .= "<br/>\n";
    $data{html} .= unescapeBR(escapeHTML($simpleDesc))."</p>\n";
}

# Producing the XML.

$data{xml} = "<?xml version='1.0' standalone='yes' encoding='utf-8'?>\n";
$data{xml} .= "<extensions>\n";
$data{xml} .= "  <details>\n    <title lang=\"$config{defaultLang}\">".
  escapeHTML($config{'repoTitle'})."</title>\n  </details>\n";
$data{xml} .= "  <plugins>\n";

foreach my $a (sort {lc $a cmp lc $b} keys(%latestMinVersionZips) ) {

    my $app = $latestMinVersionZips{$a};
    my $zip = $app->{fullpath};
    my $base = $app->{basename};

    my $titleStrings = $app->{strings}->{'PLUGIN_'.uc($base)};
    my $descStrings = $app->{strings}->{'PLUGIN_'.uc($base).'_DESC'};

    # Grab the simple description for the HTML.
    my $simpleDesc = $descStrings->{$config{defaultLang}};

    my $changeStrings = $app->{strings}->{'PLUGIN_'.uc($base).'_REPO_DESC'};
    # if you want the REPO_DESC in the HTML, too, uncomment the next line
    #$simpleDesc = $descStrings->{$config{defaultLang}};

    my $url = getURL($zip);
    my $hash = getHash($zip);
    my $minv = $app->{minVersion};
    my $maxv = $app->{maxVersion};

    # XML
    $data{xml} .= '    <plugin name="'.$base.'"'.
      ' version="'.$app->{version}.'"'.
      " minTarget=\"$minv\" maxTarget=\"$maxv\">"."\n";
    $data{xml} .= makeElements( title   => $titleStrings  );
    $data{xml} .= makeElements( desc    => $descStrings   );
    $data{xml} .= makeElements( changes => $changeStrings );
    $data{xml} .= "      <url>".escapeHTML($url)."</url>\n";
    $data{xml} .= "      <sha>$hash</sha>\n";
    if ( my $infourl = $app->{infoUrl} ) {
	$data{xml} .= "      <link>".escapeHTML($infourl)."</link>\n";
    }
    $data{xml} .= "      <creator>".escapeHTML($config{'creator'})."</creator>\n";
    $data{xml} .= "      <email>".escapeHTML($config{'emailAddress'})."</email>\n";
    $data{xml} .= "    </plugin>\n";
}
$data{xml} .= "  </plugins>\n</extensions>\n";

# Writing the output files.
my %outfiles = %{$config{files}};
foreach my $type (keys %outfiles) {
    my $file = $outfiles{$type};
    if ( $test ) {
	warn( "Would write ", length($data{$type}),
	      " bytes to $file but we're testing only\n" );
	next;
    }
    elsif ( $verbose ) {
	warn( "Writing ", length($data{$type}),
	      " bytes to $file ...\n" );
    }

    if ( open( my $f, ">:utf8", $file ) ) {
	print $f $data{$type};
	close $f;
    }
    else {
	warn("$file: Write error [$!]\n" );
    }
}

exit;

################ Subroutines ################

sub escapeHTML($) {
    my ( $t ) = @_;
    return '' unless defined $t;
    $t =~ s/&/&amp;/g;
    $t =~ s/</&lt;/g;
    $t =~ s/>/&gt;/g;
    $t =~ s/"/&quot;/g;
    return $t;
}

sub unescapeBR($) {
    my $text = shift;
    $text =~ s/\&lt\;[bB][rR]\s*\/?\&gt\;/<br\/>/sig;
    return $text;
}

sub getMtime($) {
    my ( $file ) = @_;
    my @finfo = lstat($file);
    return $finfo[9];
}

sub getMTimeString($) {
    my ( $time ) = @_;
    my @l = localtime($time);
    return sprintf('%04d/%02d/%02d', 1900+$l[5], 1+$l[4], $l[3] );
}

sub makeElements($$) {
    my ( $attr, $h ) = @_;
    my $ret = '';
    foreach my $lang ( keys %$h ) {
	$ret .= "      ".
	  "<${attr} lang=\"${lang}\">".
	  escapeHTML($h->{$lang}).
	  "</${attr}>\n";
    }
    return $ret;
}

sub getHash($) {
    my ( $file ) = @_;

    if ( $INC{'Digest/SHA1'} ) {
	my $h = new Digest::SHA1;
	open( my $f, "<", $file );
	$h->addfile($f);
	return $h->hexdigest();
    }

    my $ret = `sha1sum -b $file`;
    $ret =~ s/\s.*$//s;
    return $ret;
}

sub getURL($) {
    my ( $file ) = @_;
    $file = substr( $file, length($config{localWebDir} ) );
    return $config{urlBase} . $file;
}

sub getBasename($) {
    my ( $file ) = @_;
    my $base = fileparse( $file, qr/\.zip$/i );
    return () unless $base =~ /^(.*?)[-_](.*)/;
    $base = $1;
    my $version = $2;
    $version =~ s/^[\_\-]*//;
    return ( $base, $config{versionPrefix}.$version );
}

sub findZips($$) {
    my ( $dir, $excludeRegexp ) = @_;

    my @zips = ();

    find( { no_chdir => 1, wanted => sub {
	      return unless /\.zip$/i;
	      return if defined($excludeRegexp) && /$excludeRegexp/;
	      my $item = getTargetInfo( $File::Find::name );
	      return unless $item;
	      push( @zips, $item );
	  } }, $dir );

    return @zips;
}

sub getTargetInfo($) {
    my ( $fullpath ) = @_;

    warn( "Processing: $fullpath ...\n" ) if $verbose;

    # $pluginName = $pluginZipName - ".zip" suffix
    my ( $pluginName, $version ) = getBasename($fullpath);
    unless ( $pluginName ) {
	warn("$fullpath: SKIPPED (Not pluginname-version.zip)\n");
	return;
    }

    my %ret = ( fullpath => $fullpath,
		basename => $pluginName,
		mtime    => getMtime($fullpath),
	      );

    my $zip = Archive::Zip->new;
    unless ( $zip->read($fullpath) == AZ_OK ) {
	warn("$fullpath: SKIPPED (Not a zip?)\n");
	return;
    }

    # Read install.xml (catdir($fulltemp,$pluginName,'install.xml')
    my @m = $zip->membersMatching( '^(.*)/install\.xml$' );
    if ( @m != 1 ) {
	warn("$fullpath: SKIPPED (Must have exactly one 'install.xml')\n");
	return;
    }
    unless ( dirname( $m[0]->fileName ) eq $pluginName ) {
	warn( "$fullpath: SKIPPED (", $m[0]->fileName,
	      " must be in folder $pluginName)\n" );
	return;
    }

    my $data = $zip->contents($m[0]);
    my $xml = new XML::Simple;
    $data = $xml->XMLin($data) if $data;
    unless ( $data ) {
	warn("$fullpath: SKIPPED (No data for 'install.xml')\n");
	return;
    }

    my $targetApp = $data->{targetApplication};
    unless ( $targetApp ) {
	warn("$fullpath: SKIPPED (Missing target app info)\n");
	return;
    }

    @m = $zip->membersMatching( '^'.qr($pluginName).'(/.*)?/Plugin\.pm$' );
    unless ( @m == 1 ) {
	warn("$fullpath: SKIPPED (Must have exactly one 'Plugin.pm')\n");
	return;
    }

    my $optionsURL = $data->{optionsURL};
    if ( $optionsURL ) {
	my $p = "$pluginName/HTML/$config{defaultLang}/$optionsURL";
	@m = $zip->membersMatching( '^'.qr($p).'$' );
	unless ( @m == 1 ) {
	    warn("$fullpath: Must have exactly one '$p'\n");
	    return;
	}
	@m = $zip->membersMatching( '^'.qr($pluginName).'(/.*)?/Settings\.pm$' );
	unless ( @m == 1 ) {
	    warn("$fullpath: SKIPPED (Must have exactly one 'Settings.pm')\n");
	    return;
	}
    }

    my $strings = {};
    foreach my $m ( $zip->membersMatching( '(.*/)?strings\.txt$' ) ) {
	my $data = $zip->contents($m);
	my $key = '';
	foreach my $line ( split( /[\r\n]+/, $data ) ) {
	    next unless /\S/;
	    if ( $key && $line =~ m/\t(\w+)\t(.*)/ ) {
		my ( $lang, $val ) = ( $1, $2 );
		if ( !defined( $strings->{$key}{$lang} ) ) {
		    $strings->{$key}{$lang} = '';
		}
		$strings->{$key}{$lang} .= $val;
	    }
	    elsif ( $line =~ /^(\w+)/ ) {
		$key = $1;
	    }
	    else {
		warn( $m->fileName, ": unprocessable line\n", $line, "\n" );
	    }
	}
    }
    $ret{strings} = $strings;

    $ret{minVersion} = $targetApp->{minVersion};
    $ret{maxVersion} = $targetApp->{maxVersion};
    if ( $ret{minVersion} eq '7.0a' ) {
	$ret{'minVersion'} = '7.0';
    }
    if ( $ret{minVersion} =~ m/^([0-9]*)/ ) {
	my $m = $1;
	if ( $ret{maxVersion} eq '*' ) {
	    $ret{maxVersion} = $m.'.*';
	}
    }
    $ret{version} = $data->{version};

    if ( -f catdir( $config{infoUrlSource}, "$pluginName.html" ) ) {
	$ret{infoUrl} = $config{infoUrlBase} . "/$pluginName.html";
    }

    dumper(\%ret) if $debug;
    return \%ret;
}

sub dumper($) {
    my ( $ref ) = @_;
    eval { require DDumper; DDumper($ref) }
      or eval { require Data::Dumper; warn Data::Dumper::Dumper($ref) }
      or warn("$@");
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally
    my $man = 0;		# handled locally

    my $pod2usage = sub {
        # Load Pod::Usage only if needed.
        require Pod::Usage;
        Pod::Usage->import;
        &pod2usage;
    };

    # Process options.
    if ( @ARGV > 0 ) {
	GetOptions('ident'	=> \$ident,
		   'verbose+'	=> \$verbose,
		   'quiet'	=> sub { $verbose = 0 },
		   'trace'	=> \$trace,
		   'test|n'	=> \$test,
		   'help|?'	=> \$help,
		   'man'	=> \$man,
		   'debug'	=> \$debug)
	  or $pod2usage->(2);
    }
    if ( $ident or $help or $man ) {
	print STDERR ("This is $my_package [$my_name $my_version]\n");
    }
    if ( $man or $help ) {
	$pod2usage->(1) if $help;
	$pod2usage->(VERBOSE => 2) if $man;
    }
}

__END__

################ Documentation ################

=head1 NAME

mkrepo - create repo data for Logitech Media Server Plugins

=head1 SYNOPSIS

mkrepo [options] [ profile ]

 Options:
   --title=XXX		repository title
   --repodir=XXX	where the plugins are on disk
   --repobase=XXX	where the plugins are on the web
   --ident		shows identification
   --help		shows a brief help message and exits
   --man                shows full documentation and exits
   --verbose		provides more verbose information
   --quiet		runs as silently as possible
   --test		proecc but do not write repo files

=head1 OPTIONS

=over 8

=item B<--title=>I<XXX>

Specifies the title for the repository.
See the config section of this program.

=item B<--repodir=>I<XXX>

Specifies the directory on disk where the plugin zips can be found.
See the config section of this program.

=item B<--repobase=>I<XXX>

Specifies the web localtion where the plugin zips can be found.
See the config section of this program.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--ident>

Prints program identification.

=item B<--verbose>

Provides more verbose information.
This option may be repeated to increase verbosity.

=item B<--quiet>

Suppresses all non-essential information.

=item B<--test>

Process all but do not write repository files.

=item I<profile>

The repository profile.

=back

=head1 DESCRIPTION

B<This program> will process the plugin zips found in the I<repodir>
and create the repository xml and html data files.

Please read (and adjust) the config section of the program source,
although all necessary config data can be specified on the command
line as well.

There are two predefined profiles: C<live> and C<test> (default). With
C<test>, repository data files will have C<-test> appended to their
names.

=head1 BUGS AND DEFICIENCIES

This program is based on a similar program written by Peter Watkins.
It has been thoroughly revised and updated. Consider it a new program,
which implies that there may be rough edges.

=head1 SUPPORT AND DOCUMENTATION

Development of this module takes place on GitHub:
https://github.com/sciurius/LMS-Plugin-tools.

You can find documentation for this module with the perldoc command.

    perldoc mkrepo.pl

Please report any bugs or feature requests using the issue tracker on
GitHub.

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2020 by Johan Vromans

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
