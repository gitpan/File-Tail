use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#--- Installation check
 
sub chk_version
{
 my($pkg,$wanted,$msg) = @_;
 
 local($|) = 1;
 print "Checking for $pkg...";
 
 eval { my $p; ($p = $pkg . ".pm") =~ s#::#/#g; require $p; };
 
 my $vstr = ${"${pkg}::VERSION"} ? "found v" . ${"${pkg}::VERSION"}
                                 : "not found";
 my $vnum = ${"${pkg}::VERSION"} || 0;
 
 print $vnum >= $wanted ? "ok\n" : " " . $vstr . "\n";
 
 $vnum >= $wanted;
}
 

chk_version("FileHandle",0) or 
    die ("To install this module, you will need the FileHandle module,\n".
	 "which should be part fo the normal distribution");

chk_version("File::stat",0) or 
    die ("To install this module, you will need the File::stat module,\n".
	 "which should be part of your perl distribution\n");

chk_version("IO::Seekable",0) or
    die ("To install this module, you will need the IO::Seekable module,\n".
	 "Seekable.pm from CPAN/modules/by-module/IO/IO-x.x.tar.gz\n");

chk_version("Time::HiRes",1.12) or 
    die ("To install this module, you will need the Time::HiRes module,\n".
	 "version 1.12 or later, \n".
	 "available from CPAN/modules/by-module/Time/Time-HiRes-x.x.tar.gz\n");

WriteMakefile(
	      'NAME'	=> 'File::Tail',
	      'VERSION_FROM' => 'Tail.pm', # finds $VERSION
#	      'NOECHO' => "",
	      'PREREQ_PM' => \%prereq
);
