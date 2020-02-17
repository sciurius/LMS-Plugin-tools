#!/usr/bin/perl
#
# mkrepo.pl
#
# Perl/Linux script to create XML for SC 7.3 
# Add Extensions plugin's use
#
# Usage: set variables, then
# 	./mkrepo.pl profileName
#
# Copyright (c) 2008-2010 Peter Watkins. All Rights Reserved.
# Licensed under terms of the GNU General Public License
#
# $Id: mkrepo.pl,v 1.16 2010/01/01 14:39:03 peterw Exp peterw $

my %config;

# --------------- variables ----------------------
# (each can be overriden per-profile)

# who offers these
$config{'creator'} = 'Watkins, Peter';

# creator's email address
$config{'emailAddress'} = 'peterw@tux.org';

# default language (for HTML)
$defaultLang = 'EN';

# where to make tempdirs
# (this script will unpack all web-accessible ZIP files
#  in case different versions have different targets, e.g.
#  if MyPlugin-1.0 has minVersion=7.0+, maxVersion=7.3*
#  and MyPlying-2.0 has minVersion=7.2, maxVersion=7.5*
#  this script will make XML entries for both ZIP files)
$tmpdirParent = '/tmp';

# repo description
$config{'repoTitle'} = "Peter Watkins' SqueezeCenter extensions";

# copy of web content (where we look for zip files)
$config{'localWebDir'} = $ENV{HOME}.'/web/slim/slim7';

# where the source code is -- NOTE: this script looks
# at this, NOT the zip file contents, for strings to use
$config{'codeDir'} = $ENV{HOME}.'/code/slim/slim7';
# string info: 
# 	title (both) =  PLUGIN_{pluginName}
# 	desc (both)  =  PLUGIN_{pluginName}_DESC
# 	changes (XML)   =  PLUGIN_{pluginName}_REPO_DESC

# will change ${'localWebDir'}/$somepath to ${'urlBase'}/$somepath
# for <url> URLs in the repo XML
$config{'urlBase'} = 'http://www.tux.org/~peterw/slim/slim7';

# look here for ${pluginName}.html info file
$config{'infoUrlSource'} = $ENV{HOME}.'/web/slim';

# will change ${'infoUrlSource'}/$somepath to ${'infoUrlBase'}/somepath
# for <link> URLs in the repo XML
$config{'infoUrlBase'} = 'http://www.tux.org/~peterw/slim';

# prepend to version in zip name (my zip files have names
# like MyApp-7a1.zip while install.xml has version 0.7a1; the 
# version in the repo XML should match install.xml)
$config{'versionPrefix'} = '';	
# --------------- variables ----------------------

# --------------- profiles -----------------------
my %profiles = (
	'live' => { 
			'files' =>	{ $config{'localWebDir'}."/repodata.xml" => "xml",
			  		$config{'localWebDir'}."/repodata.html" => "html" }, 
			# exclude files under directories whose name ends in "-test"
			'excludeRegexp' => 'TESTING',
			'codeDir' => $ENV{HOME}.'/code/slim/slim7/Published/live',
		},

	'test' => { 
			'files' =>	{ $config{'localWebDir'}."/repodata-test.xml" => "xml",
			  		$config{'localWebDir'}."/repodata-test.html" => "html" }, 
			# don't exclude any files
			'excludeRegexp' => undef,
			'codeDir' => $ENV{HOME}.'/code/slim/slim7/Published/test',
			'repoTitle' => "Peter Watkins' SqueezeCenter extensions (TEST collection)",
		},
);
# --------------- profiles -----------------------

use File::Spec::Functions qw(:ALL);
use File::Basename;
use File::Path;
use XML::Simple;
use CGI;
use POSIX qw(strftime);
#use Digest::SHA1;

my %latestZips;
my %latestMinVersionZips;
my %mtimes;
my %tempdirs;

my $appname = $0;
if ( scalar(@ARGV) < 1 ) {
	&usage();
}
my $profileName = $ARGV[0];
if ( (!defined($profiles{$profileName})) || (ref($profiles{$profileName}) ne 'HASH') ) {
	&usage();
}

# test tmpdir
if ( (! -d $tmpdirParent) || (! -w $tmpdirParent) || (! chdir $tmpdirParent) ) {
	print STDERR "Unable to use temp directory \"$tmpdirParent\"\n";
	exit 2;
}

my %chosenProfile = %{$profiles{$profileName}};
foreach my $k (keys %chosenProfile) {
	$config{$k} = $chosenProfile{$k};
}

# find all my zips
my @allzips = &findZips($config{'localWebDir'},$config{excludeRegexp});

# figure out what's the latest for each plugin
foreach my $zipinfo ( @allzips ) {
	my $zip = $zipinfo->{fullpath};
	my $base = $zipinfo->{basename};
	my $version = $zipinfo->{version};
	my $thismtime = $zipinfo->{mtime};
	# for this plugin
	if ( defined($base) && (!defined($latestZips{$base})) ) {
		$mtimes{$base} = &getMTimeString($thismtime);
		$latestZips{$base} = $zipinfo;
	} else {
		my $oldmtime = &getMtime($latestZips{$base}->{fullpath});
		if ( $thismtime > $oldmtime ) {
			$latestZips{$base} = $zipinfo;
			$mtimes{$base} = &getMTimeString($thismtime);
		}
	}
	# for this plugin at this minVersion
	my $minv = $zipinfo->{minVersion};
	if ( defined($base.$minv) && (!defined($latestMinVersionZips{$base.$minv})) ) {
		$mtimes{$base.$minv} = &getMTimeString($thismtime);
		$latestMinVersionZips{$base.$minv} = $zipinfo;
	} else {
		my $oldmtime = &getMtime($latestMinVersionZips{$base.$minv}->{fullpath});
		if ( $thismtime > $oldmtime ) {
			$latestMinVersionZips{$base.$minv} = $zipinfo;
			$mtimes{$base.$minv} = &getMTimeString($thismtime);
		}
	}
}

my %data;
# the HTML intro
$data{'html'} = '';
foreach my $a (sort {lc $a cmp lc $b} keys %latestZips) {
	my $app = $latestZips{$a};
	my $zip = $app->{fullpath};
	my ($base,$version) = &getBasename($zip);
	my $codeLoc = catdir($config{'codeDir'},$base);
	my %titleStrings;
	my $titleString = 'PLUGIN_'.uc($base);
	&getStrings($base,$zip,$titleString,$codeLoc,\%titleStrings);
	my %descStrings;
	my $descString = 'PLUGIN_'.uc($base).'_DESC';
	&getStrings($base,$zip,$descString,$codeLoc,\%descStrings);
	# grab the simple description for the HTML
	my $simpleDesc = $descStrings{$defaultLang};
	my %changeStrings;
	my $changeString = 'PLUGIN_'.uc($base).'_REPO_DESC';
	&getStrings($base,$zip,$changeString,$codeLoc,\%changeStrings);
	# if you want the REPO_DESC in the HTML, too, uncomment the next line
	#$simpleDesc = $descStrings{$defaultLang};
	my $url = &getURL($zip);
	my $hash = &getHash($zip);
	my $infourl = &getInfoURL($base);	# might be undef
	my $mtime = &getMTimeString($app->{mtime});
	# HTML
	if ( defined($infourl) ) {
		$data{'html'} .= "<p><a href=\"".CGI::escapeHTML($infourl)."\">".CGI::escapeHTML($titleStrings{$defaultLang})."</a><br/>\n";
	} else {
		$data{'html'} .= '<p>'.CGI::escapeHTML($titleStrings{$defaultLang})."<br/>\n";
	}
	$data{'html'} .= "v${version}, $mtime<br />\n";
	$data{'html'} .= &unescapeBR(CGI::escapeHTML($simpleDesc))."</p>\n";
}
# the XML intro
$data{'xml'} = "<extensions>\n";
$data{'xml'} .= "<details>\n<title lang=\"${defaultLang}\">".CGI::escapeHTML($config{'repoTitle'})."</title>\n</details>\n";
$data{'xml'} .= "<plugins>\n";
foreach my $a (sort {lc $a cmp lc $b} keys %latestMinVersionZips) {
	my $app = $latestMinVersionZips{$a};
	my $zip = $app->{fullpath};
	my ($base,$version) = &getBasename($zip);
	my $codeLoc = catdir($config{'codeDir'},$base);
	my %titleStrings;
	my $titleString = 'PLUGIN_'.uc($base);
	&getStrings($base,$zip,$titleString,$codeLoc,\%titleStrings);
	my %descStrings;
	my $descString = 'PLUGIN_'.uc($base).'_DESC';
	&getStrings($base,$zip,$descString,$codeLoc,\%descStrings);
	# grab the simple description for the HTML
	my $simpleDesc = $descStrings{$defaultLang};
	my %changeStrings;
	my $changeString = 'PLUGIN_'.uc($base).'_REPO_DESC';
	&getStrings($base,$zip,$changeString,$codeLoc,\%changeStrings);
	# if you want the REPO_DESC in the HTML, too, uncomment the next line
	#$simpleDesc = $descStrings{$defaultLang};
	my $url = &getURL($zip);
	my $hash = &getHash($zip);
	my $infourl = &getInfoURL($base);	# might be undef
	my $minv = $app->{minVersion};
	my $maxv = $app->{maxVersion};
	# XML
	$data{'xml'} .= '<plugin name="'.$base.'" version="'.$version."\" minTarget=\"$minv\" maxTarget=\"$maxv\">"."\n";
	$data{'xml'} .= &makeElements('title',\%titleStrings);
	$data{'xml'} .= &makeElements('desc',\%descStrings);
	$data{'xml'} .= &makeElements('changes',\%changeStrings);
	$data{'xml'} .= "<url>".CGI::escapeHTML($url)."</url>\n";
	$data{'xml'} .= "<sha>$hash</sha>\n";
	if ( defined($infourl) ) {
		$data{'xml'} .= "<link>".CGI::escapeHTML($infourl)."</link>\n";
	}
	$data{'xml'} .= "<creator>".CGI::escapeHTML($config{'creator'})."</creator>\n";
	$data{'xml'} .= "<email>".CGI::escapeHTML($config{'emailAddress'})."</email>\n";
	$data{'xml'} .= "</plugin>\n";
}
# finish XML
$data{'xml'} .= "</plugins>\n</extensions>\n";

my %outfiles = %{$config{'files'}};
foreach my $file (keys %outfiles) {
	print "writing $outfiles{$file} to $file\n";
	if (open(F,">$file")) {
		print F $data{$outfiles{$file}};
		close F;
	} else {
		print STDERR "Error writing \"$file\"n";
	}
}

&removeTempDirs();

exit;

sub unescapeBR($) {
	my $text = shift;
	$text =~ s/\&lt\;[bB][rR]\s*\/?\&gt\;/<br\/>/sig;
	return $text;
}

sub usage() {
	print STDERR "Usage: $appname profileName\n";
	print STDERR "Available profiles: ".join(', ',(sort keys %profiles))."\n";
	exit 1;
}

sub getMTimeString($) {
	my $time = shift;
	my @l = localtime($time);
	return strftime('%Y/%m/%d',@l);
}

sub makeElements($$) {
	my ($attrname,$hashPtr) = @_;
	my $ret = '';
	foreach my $lang (keys %$hashPtr) {
		$ret .= "<${attrname} lang=\"${lang}\">".CGI::escapeHTML($hashPtr->{$lang})."</${attrname}>\n";
	}
	return $ret;
}

sub getStrings($$$$$) {
	my ($basename,$zipfile,$tokenName,$codeLoc,$hashPtr) = @_;
	my $stringFile = catdir($tempdirs{$zipfile},$basename,'strings.txt');
	if (! open(F,'<'.$stringFile) ) {
		return;
	}
	my $found = 0;
	while (my $line = <F>) {
		$line =~ s/[\r\n]//;
		if ( $found == 1 ) {
			if ( $line =~ m/\t(\w*)\t(.*)$/ ) {
				my ($lang,$val) = ($1,$2);
				if (! defined($hashPtr->{$lang}) ) {
					$hashPtr->{$lang} = '';
				}		
				$hashPtr->{$lang} .= $val;
			} else {
				# done with this token
				close F;
				return;
			}
		} else {
			if ( $line eq $tokenName ) {
				$found = 1;
			}
		}
	}
	close F;
	return;
}

sub getInfoURL($) {
	my $base = shift;
	if ( -f $config{'infoUrlSource'}."/${base}.html" ) {
		return $config{'infoUrlBase'} . '/' . $base . '.html';
	}
	return undef;
}

sub getHash($) {
	my $file = shift;
#	my $h = new Digest::SHA1;
#	open(F,"<$file");
#	$h->addfile(F);
#	my $ret = $h->hexdigest();
#	close F;
	my $ret = `sha1sum -b $file`;
	$ret =~ s/\s.*$//;
	$ret =~ s/[^a-z0-9]//sig;
	return $ret;
}

sub getURL($) {
	my $file = shift;
	$file = substr($file,length($config{'localWebDir'}));
	return $config{'urlBase'} . $file;
}

sub getBasename($) {
	my $file = shift;
	my $base = basename($file);
	# strip the extra info
	$base =~ s/^([a-zA-Z0-9]*)(.*)$/$1/;
	my $version = $2;
	# strip separators
	$base =~ s/[\_\-]*$//;
	$version =~ s/^[\_\-]*//;
	$version =~ s/\.zip$//sig;
	return ($base,$config{'versionPrefix'}.$version);
}

sub getMtime($) {
	my $file = shift;
	my @finfo = lstat($file);
	return $finfo[9];
}

sub findZips($$) {
	my $dir = shift;
	my $excludeRegexp = shift;
	my @lookin = ();
	my @zips = ();
	if (! opendir(D,$dir) ) {
		return @zips;
	}
	while (my $di = readdir(D)) {
		my $item;
		$item->{fullpath}  = catdir($dir,$di);
		if ( $di =~ m/^\.{1,2}$/ ) {
			# this or parent; ignore
		} elsif ( -d $item->{fullpath} ) {
			push @lookin, $item->{fullpath};
		} elsif ( (-f $item->{fullpath}) && ($di =~ m/\.zip$/i) ) {
			if ( (!defined($excludeRegexp)) || ($item->{fullpath} !~ m/$excludeRegexp/) ) {
				# add more items to $item for each keyed value in $targetInfo
				my $targetInfo = &getTargetInfo($item->{fullpath},$di);
				foreach my $k (keys %$targetInfo) {
					$item->{$k} = $targetInfo->{$k};
				}
				push @zips, $item;
			}
		}
	}
	closedir D;
	foreach my $d ( @lookin ) {
		my @add = &findZips($d,$excludeRegexp);
		push @zips, @add;
	}
	return @zips;
}

sub getTargetInfo($$) {
	my ($fullpath,$pluginZipName) = @_;
	# $pluginName = $pluginZipName - ".zip" suffix
	my ($pluginName,$version) = &getBasename($fullpath);
	# make temp dir
	my $dirMade = 0;
	my $fulltemp;
	while ($dirMade == 0) {
		my $d = 'mkrepo.'.rand(999999999);
		$fulltemp = catdir($tmpdirParent,$d);
		if ( mkdir($fulltemp,0700) ) {
			if ( chdir($fulltemp) ) {
				$dirMade = 1;
				$tempdirs{$fullpath} = $fulltemp;
			} else {
				print STDERR "Error using tempdir \"$fulltemp\"\n";
			}
		}
	}
	# unzip plugin ($fullpath)
	system("unzip","-q",$fullpath);
	# read install.xml (catdir($fulltemp,$pluginName,'install.xml')
	my $installFile = catdir($fulltemp,$pluginName,'install.xml');
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
	$retHash{'minVersion'} = $targetApp->{minVersion};
	$retHash{'maxVersion'} = $targetApp->{maxVersion};
	if ( $retHash{'minVersion'} eq '7.0a' ) {
		$retHash{'minVersion'} = '7.0';
	}
	if ( $retHash{'minVersion'} =~ m/^([0-9]*)/ ) {
		my $m = $1;
		if ( $retHash{'maxVersion'} eq '*' ) {
			$retHash{'maxVersion'} = $m.'.*';
		}
	}
	$retHash{'version'} = $data->{version};
	$retHash{'basename'} = $pluginName;
#print STDERR "$fullpath: minVersion ".$retHash{'minVersion'}."\n";
	my @zipInfo = stat($fullpath);
	$retHash{'mtime'} = $zipInfo[9];
	return \%retHash;	
}

sub removeTempDirs {
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
