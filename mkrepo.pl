#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Mon Feb 17 17:49:53 2020
# Last Modified By: Johan Vromans
# Last Modified On: Mon Feb 17 21:50:02 2020
# Update Count    : 28
# Status          : Unknown, Use with caution!

# Based on code written by Peter Watkins.
# Copyright (c) 2008-2010 Peter Watkins. All Rights Reserved.
# Licensed under terms of the GNU General Public License

################ Common stuff ################

use strict;
use warnings;

# Package name.
my $my_package = 'Sciurix';
# Program name and version.
my ($my_name, $my_version) = qw( mkrepo 0.001 );

################ Configuration ################

# Global config.

my %config =
  ( creator => 'Johan Vromans',

    # Creator's email address.
    emailAddress => 'jvromans@squirrel.nl',

    # Default language (for HTML).
    defaultLang => 'EN',

    # Repo description.
    repoTitle => "Johan's LMS plugins",

    # Where we look for zip files.
    localWebDir => $ENV{HOME}.'/src/LMS_Plugins/dist',

    # Where the source code is -- NOTE: this script looks
    # at this, NOT the zip file contents, for strings to use
    codeDir => $ENV{HOME}.'/src/LMS_Plugins',
    # String info:
    # 	title (both) =  PLUGIN_{pluginName}
    # 	desc (both)  =  PLUGIN_{pluginName}_DESC
    # 	changes (XML)   =  PLUGIN_{pluginName}_REPO_DESC

    # Will change ${'localWebDir'}/$somepath to ${'urlBase'}/$somepath
    # for <url> URLs in the repo XML
    urlBase => 'http://album.squirrel.nl/lms/plugins',

    # Look here for ${pluginName}.html info file.
    infoUrlSource => $ENV{HOME}.'/src/LMS_Plugins',

    # Will change $infoUrlSource/somepath to $infoUrlBase/somepath
    # for <link> URLs in the repo XML
    infoUrlBase => 'http://www.tux.org/~peterw/slim',

    # Prepend to version in zip name (my zip files have names
    # like MyApp-7a1.zip while install.xml has version 0.7a1; the 
    # version in the repo XML should match install.xml)
    versionPrefix => '',

    # End of config values.
  );

# Define two profiles: 'test' and 'live'.

my %profiles =
  (
   live =>
   { files   =>	{ $config{localWebDir}."/repodata.xml" => "xml",
		  $config{localWebDir}."/repodata.html" => "html" },
     # exclude files under directories whose name ends in "-test"
     excludeRegexp => undef,
#     codeDir => $ENV{HOME}.'/code/slim/slim7/Published/live',
   },
   test =>
   { files   =>	{ $config{localWebDir}."/repodata-test.xml" => "xml",
		  $config{localWebDir}."/repodata-test.html" => "html" },
     excludeRegexp => undef,
#     codeDir => $ENV{HOME}.'/code/slim/slim7/Published/test',
     repoTitle => "LMS extensions (TEST collection)",
   },
);


################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $profile = "test";

my $verbose = 1;		# verbose processing

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

# Where to make tempdirs
# (this script will unpack all web-accessible ZIP files
#  in case different versions have different targets, e.g.
#  if MyPlugin-1.0 has minVersion=7.0+, maxVersion=7.3*
#  and MyPlying-2.0 has minVersion=7.2, maxVersion=7.5*
#  this script will make XML entries for both ZIP files)

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';
my $tmpdirParent = $TMPDIR;

################ The Process ################

use File::Spec::Functions qw(:ALL);
use File::Basename;
use File::Path;
use XML::Simple;
use CGI;
use POSIX qw(strftime);
#use Digest::SHA1;

sub unescapeBR($);
sub usage();
sub getMTimeString($);
sub makeElements($$);
sub getStrings($$$$$);
sub getInfoURL($);
sub getHash($);
sub getURL($);
sub getBasename($);
sub getMtime($);
sub findZips($$);
sub getTargetInfo($$);
sub removeTempDirs();

my %latestZips;
my %latestMinVersionZips;
my %mtimes;
my %tempdirs;

my $profileName = $ARGV[0] || $profile;
unless ( exists( $profiles{$profileName} ) ) {
    app_usage();
}

# Test tmpdir
unless ( -d -w $tmpdirParent && chdir($tmpdirParent) ) {
    warn("Unable to use temp directory \"$tmpdirParent\"\n");
    exit 2;
}

# Copy profile data into config.
my %chosenProfile = %{$profiles{$profileName}};
while ( my ($k,$v) = each(%chosenProfile) ) {
    $config{$k} = $v;
}

# Find all zips.
my @allzips = &findZips( $config{localWebDir}, $config{excludeRegexp} );

# Figure out what's the latest for each plugin.
foreach my $zipinfo ( @allzips ) {
    my $zip = $zipinfo->{fullpath};
    my $base = $zipinfo->{basename};
    my $version = $zipinfo->{version};
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
	    $mtimes{$base} = &getMTimeString($thismtime);
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

my %data;
# the HTML intro
$data{'html'} = '';
foreach my $a ( sort {lc $a cmp lc $b} keys(%latestZips) ) {
    my $app = $latestZips{$a};
    my $zip = $app->{fullpath};
    my ( $base, $version ) = getBasename($zip);
    my $codeLoc = catdir( $config{codeDir}, $base );

    my %titleStrings;
    my $titleString = 'PLUGIN_'.uc($base);
    getStrings( $base, $zip, $titleString, $codeLoc, \%titleStrings );

    my %descStrings;
    my $descString = 'PLUGIN_'.uc($base).'_DESC';
    getStrings( $base, $zip, $descString, $codeLoc, \%descStrings );

    # Grab the simple description for the HTML.
    my $simpleDesc = $descStrings{$config{defaultLang}};
    my %changeStrings;
    my $changeString = 'PLUGIN_'.uc($base).'_REPO_DESC';
    getStrings( $base, $zip, $changeString, $codeLoc, \%changeStrings );
    # if you want the REPO_DESC in the HTML, too, uncomment the next line
    #$simpleDesc = $descStrings{$config{defaultLang}};

    my $url = getURL($zip);
    my $hash = getHash($zip);
    my $infourl = getInfoURL($base);	# might be undef
    my $mtime = getMTimeString($app->{mtime});

    # HTML
    if ( defined($infourl) ) {
	$data{html} .= "<p><a href=\"".CGI::escapeHTML($infourl)."\">".CGI::escapeHTML($titleStrings{$config{defaultLang}})."</a><br/>\n";
    }
    else {
	$data{html} .= '<p>'.CGI::escapeHTML($titleStrings{$config{defaultLang}})."<br/>\n";
    }
    $data{html} .= "v${version}, $mtime<br />\n";
    $data{html} .= unescapeBR(CGI::escapeHTML($simpleDesc))."</p>\n";
}

# The XML intro.
$data{xml} = "<extensions>\n";
$data{xml} .= "<details>\n<title lang=\"$config{defaultLang}\">".CGI::escapeHTML($config{'repoTitle'})."</title>\n</details>\n";
$data{xml} .= "<plugins>\n";

foreach my $a (sort {lc $a cmp lc $b} keys(%latestMinVersionZips) ) {
    my $app = $latestMinVersionZips{$a};
    my $zip = $app->{fullpath};
    my ( $base, $version ) = getBasename($zip);
    my $codeLoc = catdir( $config{codeDir}, $base );

    my %titleStrings;
    my $titleString = 'PLUGIN_'.uc($base);
    getStrings( $base, $zip, $titleString, $codeLoc, \%titleStrings );

    my %descStrings;
    my $descString = 'PLUGIN_'.uc($base).'_DESC';
    getStrings( $base, $zip, $descString, $codeLoc, \%descStrings );

    # Grab the simple description for the HTML.
    my $simpleDesc = $descStrings{$config{defaultLang}};

    my %changeStrings;
    my $changeString = 'PLUGIN_'.uc($base).'_REPO_DESC';
    getStrings( $base, $zip, $changeString, $codeLoc, \%changeStrings );
    # if you want the REPO_DESC in the HTML, too, uncomment the next line
    #$simpleDesc = $descStrings{$config{defaultLang}};

    my $url = getURL($zip);
    my $hash = getHash($zip);
    my $infourl = getInfoURL($base);	# might be undef
    my $minv = $app->{minVersion};
    my $maxv = $app->{maxVersion};

    # XML
    $data{xml} .= '<plugin name="'.$base.'" version="'.$version."\" minTarget=\"$minv\" maxTarget=\"$maxv\">"."\n";
    $data{xml} .= makeElements('title',\%titleStrings);
    $data{xml} .= makeElements('desc',\%descStrings);
    $data{xml} .= makeElements('changes',\%changeStrings);
    $data{xml} .= "<url>".CGI::escapeHTML($url)."</url>\n";
    $data{xml} .= "<sha>$hash</sha>\n";
    if ( defined($infourl) ) {
	$data{xml} .= "<link>".CGI::escapeHTML($infourl)."</link>\n";
    }
    $data{xml} .= "<creator>".CGI::escapeHTML($config{'creator'})."</creator>\n";
    $data{xml} .= "<email>".CGI::escapeHTML($config{'emailAddress'})."</email>\n";
    $data{xml} .= "</plugin>\n";
}

# Finish XML
$data{xml} .= "</plugins>\n</extensions>\n";

my %outfiles = %{$config{files}};
foreach my $file (keys %outfiles) {
    print "writing $outfiles{$file} to $file\n";
    if ( open( my $f, ">", $file ) ) {
	print $f $data{$outfiles{$file}};
	close $f;
    }
    else {
	warn("Error writing \"$file\"n");
    }
}

removeTempDirs();

exit;

################ Subroutines ################

sub unescapeBR($) {
    my $text = shift;
    $text =~ s/\&lt\;[bB][rR]\s*\/?\&gt\;/<br\/>/sig;
    return $text;
}

sub usage() {
    print STDERR "Usage: $0 profileName\n";
    print STDERR "Available profiles: ".join(', ',(sort keys %profiles))."\n";
    exit 1;
}

sub getMTimeString($) {
    my ( $time ) = @_;
    my @l = localtime($time);
    return sprintf('%04d/%02d/%02d', 1900+$l[5], 1+$l[4], $l[3] );
}

sub makeElements($$) {
    my ( $attrname, $hashPtr ) = @_;
    my $ret = '';
    foreach my $lang ( keys %$hashPtr ) {
	$ret .= "<${attrname} lang=\"${lang}\">".CGI::escapeHTML($hashPtr->{$lang})."</${attrname}>\n";
    }
    return $ret;
}

sub getStrings($$$$$) {
    my ( $basename, $zipfile, $tokenName, $codeLoc, $hashPtr ) = @_;
    my $stringFile = catdir( $tempdirs{$zipfile}, $basename, 'strings.txt' );
    my $f;
    if ( !open( $f, '<', $stringFile ) ) {
	return;
    }
    my $found = 0;
    while ( my $line = <$f> ) {
	$line =~ s/[\r\n]//;
	if ( $found == 1 ) {
	    if ( $line =~ m/\t(\w*)\t(.*)$/ ) {
		my ( $lang, $val ) = ( $1, $2 );
		if ( !defined( $hashPtr->{$lang} ) ) {
		    $hashPtr->{$lang} = '';
		}
		$hashPtr->{$lang} .= $val;
	    }
	    else {
		# done with this token
		close $f;
		return;
	    }
	}
	else {
	    if ( $line eq $tokenName ) {
		$found = 1;
	    }
	}
    }
    close $f;
    return;
}

sub getInfoURL($) {
    my ( $base ) = @_;
    if ( -f $config{infoUrlSource}."/${base}.html" ) {
	return $config{infoUrlBase} . '/' . $base . '.html';
    }
    return;
}

sub getHash($) {
    my $file = shift;

    my $ret;
    if ( $INC{'Digest/SHA1'} ) {
	my $h = new Digest::SHA1;
	open( my $f, "<", $file );
	$h->addfile($f);
	my $ret = $h->hexdigest();
	close $f;
    }
    else {
	$ret = `sha1sum -b $file`;
	$ret =~ s/\s.*$//;
	$ret =~ s/[^a-z0-9]//sig;
    }
    return $ret;
}

sub getURL($) {
    my ( $file ) = @_;
    $file = substr( $file, length($config{localWebDir} ) );
    return $config{urlBase} . $file;
}

sub getBasename($) {
    my ( $file ) = @_;
    my $base = basename($file);
    # Strip the extra info.
    $base =~ s/^([a-zA-Z0-9]*)(.*)$/$1/;
    my $version = $2;
    # Strip separators.
    $base =~ s/[\_\-]*$//;
    $version =~ s/^[\_\-]*//;
    $version =~ s/\.zip$//sig;
    return ( $base, $config{versionPrefix}.$version );
}

sub getMtime($) {
    my ( $file ) = @_;
    my @finfo = lstat($file);
    return $finfo[9];
}

sub findZips($$) {
    my ( $dir, $excludeRegexp ) = @_;

    my @lookin = ();
    my @zips = ();
    if ( !opendir(D,$dir) ) {
	return @zips;
    }
    while ( my $di = readdir(D) ) {
	my $item;
	$item->{fullpath}  = catdir($dir,$di);
	if ( $di =~ m/^\.{1,2}$/ ) {
	    # this or parent; ignore
	}
	elsif ( -d $item->{fullpath} ) {
	    push @lookin, $item->{fullpath};
	}
	elsif ( (-f $item->{fullpath}) && ($di =~ m/\.zip$/i) ) {
	    if ( (!defined($excludeRegexp)) || ($item->{fullpath} !~ m/$excludeRegexp/) ) {
		# add more items to $item for each keyed value in $targetInfo
		my $targetInfo = getTargetInfo($item->{fullpath},$di);
		foreach my $k (keys %$targetInfo) {
		    $item->{$k} = $targetInfo->{$k};
		}
		push @zips, $item;
	    }
	}
    }
    closedir D;
    foreach my $d ( @lookin ) {
	my @add = findZips( $d, $excludeRegexp );
	push @zips, @add;
    }
    return @zips;
}

sub getTargetInfo($$) {
    my ( $fullpath, $pluginZipName ) = @_;

    # $pluginName = $pluginZipName - ".zip" suffix
    my ( $pluginName, $version ) = getBasename($fullpath);
    # make temp dir
    my $dirMade = 0;
    my $fulltemp;
    while ( $dirMade == 0 ) {
	my $d = 'mkrepo.'.rand(999999999);
	$fulltemp = catdir($tmpdirParent,$d);
	if ( mkdir($fulltemp,0700) ) {
	    if ( chdir($fulltemp) ) {
		$dirMade = 1;
		$tempdirs{$fullpath} = $fulltemp;
	    }
	    else {
		warn("Error using tempdir \"$fulltemp\"\n");
	    }
	}
    }

    # unzip plugin ($fullpath)
    system( "unzip", "-q", $fullpath );
    # read install.xml (catdir($fulltemp,$pluginName,'install.xml')
    my $installFile = catdir( $fulltemp, $pluginName, 'install.xml' );
    my $xml = new XML::Simple;
    my $data = $xml->XMLin($installFile);
    #if (!defined($data)) { print STDERR "no data for $fullpath!\n"; }
#else { print STDERR join(', ',keys %$data)."\n"; }
	# return hash like ( 'minVersion' => $x, 'maxVersion' => $y, 'target' => $p )
    my %retHash;
    my $targetApp = $data->{targetApplication};
#if (!defined($targetApp)) { print STDERR "no target app info for $fullpath!\n"; }
#else { print STDERR join(', ',keys %$targetApp)."\n"; }
#else { print STDERR "target app data is a ".ref($targetApp)." object\n"; }
    $retHash{minVersion} = $targetApp->{minVersion};
    $retHash{maxVersion} = $targetApp->{maxVersion};
    if ( $retHash{minVersion} eq '7.0a' ) {
	$retHash{'minVersion'} = '7.0';
    }
    if ( $retHash{minVersion} =~ m/^([0-9]*)/ ) {
	my $m = $1;
	if ( $retHash{maxVersion} eq '*' ) {
	    $retHash{maxVersion} = $m.'.*';
	}
    }
    $retHash{version} = $data->{version};
    $retHash{basename} = $pluginName;
#print STDERR "$fullpath: minVersion ".$retHash{'minVersion'}."\n";
    my @zipInfo = stat($fullpath);
    $retHash{mtime} = $zipInfo[9];
    return \%retHash;
}

sub removeTempDirs() {
    foreach my $d ( keys %tempdirs ) {
	my $fulltemp = $tempdirs{$d};
	# remove temp dir ($fulltemp)
	chdir($tmpdirParent);
	rmtree($fulltemp);
# BUG
#print STDERR "remove \"$fulltemp\"\n";
    }
}

#<plugins>
#<plugin name="Alien" version="2.3b1-7.3" target="mac|unix" minTarget="7.3" maxTarget="7.3">
#<title lang="EN">Alien BBC</title>
#<desc lang="EN">Plugin to play BBC radio - mac/unix version</desc>
#<url>http://wiki.slimdevices.com/uploads/3/33/AlienUnix.zip</url>
#<sha>c75fa68cfaf925bc12e840b4f8969c86422df934</sha>
#<link>http://www.x2systems.com/alienbbc</link>
#</plugin>

exit 0;

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

sample - skeleton for GetOpt::Long and Pod::Usage

=head1 SYNOPSIS

sample [options] [file ...]

 Options:
   --ident		shows identification
   --help		shows a brief help message and exits
   --man                shows full documentation and exits
   --verbose		provides more verbose information
   --quiet		runs as silently as possible

=head1 OPTIONS

=over 8

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

=item I<file>

The input file(s) to process, if any.

=back

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do someting
useful with the contents thereof.

=cut
