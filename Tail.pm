package File::Tail;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
$VERSION = '0.85';


# Preloaded methods go here.

use FileHandle;
#use IO::Seekable; # does not define SEEK_SET in 5005.02
use File::stat;
use Carp;
use Time::HiRes qw ( time sleep ); #import hires microsecond timers

sub SEEK_SET {0;}
sub SEEK_START {1;}
sub SEEK_END {2;}


sub interval {
    my $object=shift @_;
    if (@_) {
	$object->{interval}=shift;
	$object->{interval}=$object->{maxinterval} if 
	    $object->{interval}>$object->{maxinterval};
    }
    $object->{interval};
}

sub adjustafter {
    my $self=shift;
    $self->{adjustafter}=shift if @_;
    return $self->{adjustafter};
}

sub debug {
    my $self=shift;
    $self->{"debug"}=shift if @_;
    return $self->{"debug"};
}

sub errmode {
    my($self, $mode) = @_;
    my($prev) = $self->{errormode};
 
    if (@_ >= 2) {
        ## Set the error mode.
	defined $mode or $mode = '';
	if (ref($mode) eq 'CODE') {
	    $self->{errormode} = $mode;
	} elsif (ref($mode) eq 'ARRAY') {
	    unless (ref($mode->[0]) eq 'CODE') {
		croak 'bad errmode: first item in list must be a code ref';
		$mode = 'die';
	    }
	    $self->{errormode} = $mode;
	} else {
	    $self->{errormode} = lc $mode;
	}
    }
     $prev;
} 

sub errmsg {
    my($self, @errmsgs) = @_;
    my($prev) = $self->{errormsg};
 
    if (@_ > 0) {
        $self->{errormsg} = join '', @errmsgs;
    }
 
    $prev;
} # end sub errmsg
 
 
sub error {
    my($self, @errmsg) = @_;
    my(
       $errmsg,
       $func,
       $mode,
       @args,
       );
 
    if (@_ >= 1) {
        ## Put error message in the object.
        $errmsg = join '', @errmsg;
        $self->{"errormsg"} = $errmsg;
 
        ## Do the error action as described by error mode.
        $mode = $self->{"errormode"};
        if (ref($mode) eq 'CODE') {
            &$mode($errmsg);
            return;
        } elsif (ref($mode) eq 'ARRAY') {
            ($func, @args) = @$mode;
            &$func(@args);
            return;
        } elsif ($mode eq "return") {
            return;
	} elsif ($mode eq "warn") {
	    carp $errmsg;
        } else {  # die
	    croak $errmsg;
	}
    } else {
        return $self->{"errormsg"} ne '';
    }
} # end sub error


sub copy {
    my $self=shift;
    $self->{copy}=shift if @_;
    return $self->{copy};
}

sub tail {
    my $self=shift;
    $self->{tail}=shift if @_;
    return $self->{tail};
}

sub reset_tail {
    my $self=shift;
    $self->{reset_tail}=shift if @_;
    return $self->{reset_tail};
}

sub nowait {
    my $self=shift;
    $self->{nowait}=shift if @_;
    return $self->{nowait};
}

sub method {
    my $self=shift;
    $self->{method}=shift if @_;
    return $self->{method};
}

sub input {
    my $self=shift;
    $self->{input}=shift if @_;
    return $self->{input};
}

sub maxinterval {
    my $self=shift;
    $self->{maxinterval}=shift if @_;
    return $self->{maxinterval};
}

sub resetafter {
    my $self=shift;
    $self->{resetafter}=shift if @_;
    return $self->{resetafter};
}

sub ignore_nonexistant {
    my $self=shift;
    $self->{ignore_nonexistant}=shift if @_;
    return $self->{ignore_nonexistant};
}

sub TIEHANDLE {
    my $ref=new(@_);
}

sub READLINE {
    $_[0]->read();
}

sub PRINT {
  $_[0]->error("PRINT makes no sense in File::Tail");
}

sub PRINTF {
  $_[0]->error("PRINTF makes no sense in File::Tail");
}

sub READ {
  $_[0]->error("READ not implemented in File::Tail -- use READLINE (<HANDLE>) instead");
}

sub GETC {
  $_[0]->error("GETC not (yet) implemented in File::Tail -- use READLINE (<HANDLE>) instead");
}

sub DESTROY {
  my($this) = shift(@_);
  close($this->{"handle"});
#  undef $this->[0];
  undef $this;
  return undef;
}

sub CLOSE {
    &DESTROY(@_);
}

sub new {
    my ($pkg)=shift @_;
    $pkg=ref($pkg) || $pkg;
    unless ($pkg) {
	$pkg="File::Tail";
    } 
    my %params;
    if ($#_ == 0)  {
	$params{"name"}=$_[0];
    } else {
	if (($#_ % 2) != 1) {
	    croak "Odd number of parameters for new";
	    return undef;
	}
	%params=@_;
    }
#    my $object=$pkg->SUPER::new();
    my $object = {};
    bless $object,$pkg;
    unless (defined($params{'name'})) {
	croak "No file name given. Pass filename as \"name\" parameter";
	return;
    }
    $object->input($params{'name'});
    $object->copy($params{'cname'});
    $object->method($params{'method'} || "tail");
#    $object->buffer("");
    $object->{buffer}="";
    $object->maxinterval($params{'maxinterval'} || 60);
    $object->interval($params{'interval'} || 10);
    $object->adjustafter($params{'adjustafter'} || 10);
    $object->errmode($params{'errmode'} || "die");
    $object->resetafter($params{'resetafter'} || 
			 ($object->maxinterval*$object->adjustafter));
    $object->{"debug"}=($params{'debug'} || 0);
    $object->{"tail"}=($params{'tail'} || 0);
    $object->{"reset_tail"}=($params{'reset_tail'} || -1);
    $object->{'ignore_nonexistant'}=($params{'ignore_nonexistant'} || 0);
    $object->{lastread}=0;
    if ($object->{"method"} eq "tail") {
#	reset_pointers($object);
	$object->reset_pointers;
    }
    return $object;
}

sub position {
    my $object=shift;
    unless ($object->{tail}) {
	print "Start reading at end of file\n" if $object->{"debug"};
	$object->{curpos}=sysseek($object->{handle},0,SEEK_END);
    } elsif ($object->{tail}<0) {
	print "Start reading at start of file\n" if $object->{"debug"};
	$object->{curpos}=sysseek($object->{handle},0,SEEK_START);
    } else {
	print "Return ".$object->{"tail"}." lines.\n" 
	    if $object->{"debug"};
	my $crs=0;
	my $maxlen=sysseek($object->{handle},0,SEEK_END);
	while ($crs<$object->{"tail"}+1) {
	    my $avlen=length($object->{"buffer"})/($crs+1);
	    $avlen=80 unless $avlen;
	    my $calclen=$avlen*$object->{"tail"};
	    $calclen+=1024 if $calclen<=length($object->{"buffer"});
	    $calclen=$maxlen if $calclen>$maxlen;
	    $object->{curpos}=sysseek($object->{handle},-$calclen,SEEK_END);
	    sysread($object->{handle},$object->{"buffer"},
		    $calclen);
	    $crs=$object->{"buffer"}=~tr/\n//;
	    last if ($calclen>=$maxlen);
	}
	if ($crs>$object->{"tail"}) {
	    my $toskip=$crs-$object->{"tail"};
	    my $pos;
	    $pos=index($object->{"buffer"},"\n");
	    while (--$toskip) {
		$pos=index($object->{"buffer"},"\n",$pos+1);
	    }
	    $object->{"buffer"}=substr($object->{"buffer"},$pos+1);
	}
    }
    $object->{tail}=$object->{reset_tail};
}

sub reset_pointers {
    my $object=shift @_;
    print "reseting after ".(time()-$object->{lastread})."s\n" if $object->{"debug"};

    my $st;

    my $oldhandle=$object->{handle};
    my $newhandle=FileHandle->new;

    unless (open($newhandle,"<".$object->input)) {
	if ($object->{'ignore_nonexistant'}) {
	    return;
	}
	$object->error("Error opening ".$object->input.": $!");
	return undef;
    }
    
    if (defined($oldhandle)) {
	# If file has not been changed since last OK read do not do anything
	$st=stat($newhandle);
	# lastread uses fractional time, stat doesn't. This can cause false
        # negatives.
	if (($st->mtime<int($object->{lastread}))) {
	    print "File not modified since last read. Reset skipped.\n" if $object->{"debug"};
	    return;
	}
	$object->{handle}=$newhandle;
                                             #file was created after last read
#	if ($st->ctime>=int($object->{lastread}) or 
#	    $st->size<$object->{curpos}) {    
#	    $object->{curpos}=sysseek($object->{handle},0,SEEK_SET);
#	    print "Setting pointer to start\n" if $object->{"debug"};
#	} else {
#	    $object->{curpos}=sysseek($object->{handle},0,SEEK_END);
#	    print "Setting pointer to end of new file\n" if $object->{"debug"};
#	}
	$object->position;
	close($oldhandle);
    } else {                  # This is the first time we are opening this file
	$st=stat($newhandle);
	$object->{handle}=$newhandle;
	$object->position;
#	$object->{lastread}=time;
	$object->{lastread}=$st->mtime; # for better estimate on initial read
    }
    
#    if (defined($object->{cname})) {
#	return $!="Error opening ".$object->{cname}.": $!",undef 
#	    unless open($object->{cname},">>".$object->{cname});
#    }
}


sub checkpending {
   my $object=shift @_;
   unless ($object->{handle}) {
       print "Trying to find previously nonexistant file\n" 
	   if $object->{"debug"};
       $object->reset_pointers;
       unless ($object->{handle}) { # This try did not open the file either
	   print "File does not yet exist\n" if $object->{"debug"};
	   return 0;
       }
   }
   if ($object->{"debug"}) {
       print "Checkpending position = ".$object->{curpos};
       print " interval = ".$object->interval."\n";
   }
   
   my $endpos=sysseek($object->{handle},0,SEEK_END);
   if ($endpos<$object->{curpos}) { 
       $object->{curpos}=0;
   } elsif (($object->{curpos}==$endpos) 
	       && (time()-$object->{'lastread'})>$object->{'resetafter'}) {
       $object->reset_pointers;
       $endpos=sysseek($object->{handle},0,SEEK_END);
   }

#   my $endpos=sysseek($object->{handle},0,SEEK_END);
#   if ($endpos<$object->{curpos}) { 
#       $object->{curpos}=0;
#   }
   if ($endpos-$object->{curpos}) {
       sysseek($object->{handle},$object->{curpos},SEEK_SET);
   }
   return ($endpos-$object->{curpos});
}

sub read {
    my $object=shift @_;
    my $len;
    my $cnt;
    my $crs=$object->{"buffer"}=~tr/\n//; # Count newlines in buffer 
    print "read - $crs waiting in buffer\n" if $object->{"debug"};
    while (!$crs) {
	print "Reading loop entered\n" if $object->{"debug"};
	$cnt=0;
	while (!($len=$object->checkpending) && !length($object->{"buffer"})) {
	    return "" if $object->nowait;
	    sleep($object->interval);               # maybe should be adjusted?
	    if ($cnt++>$object->adjustafter) {
		$cnt=0;
		$object->interval($object->interval*10);
	    }
	}
	if (length($object->{"buffer"})) {
	    # this means the file was reset AND a tail -n was active
	    $crs=$object->{"buffer"}=~tr/\n//; # Count newlines in buffer 
	    next if $crs;
	}
	$len=sysread($object->{handle},$object->{"buffer"},
		$len,length($object->{"buffer"}));
	$object->{curpos}=sysseek($object->{handle},
				  $object->{curpos}+$len,SEEK_SET);
    
	$crs=$object->{"buffer"}=~tr/\n//;
	if ($object->{"debug"}) {
	    print "Got something ($len). there are now $crs newlines in buffer (";
	    print length($object->{"buffer"})." bytes)\n";
	}

	next unless $crs;
#    $object->{interval}=(time-$object->{lastread})/$crs;
	my $tmp=time; 
	$object->interval(($tmp-($object->{lastread}))/$crs);
	$object->{lastread}=$tmp;
    }
    unless (wantarray) {
	my $str=substr($object->{"buffer"},0,
		       1+index($object->{"buffer"},"\n"));
	$object->{"buffer"}=substr($object->{"buffer"},
				   1+index($object->{"buffer"},"\n"));
	return $str;
    } else {
#	my @str=split(/\n/,$object->{"buffer"});
#	$object->{"buffer"}="";
#	return(@str);
	my @str;
	while (index($object->{"buffer"},"\n")>-1) {
	    push(@str,substr($object->{"buffer"},0,
			     1+index($object->{"buffer"},"\n")));
	    $object->{"buffer"}=substr($object->{"buffer"},
				       1+index($object->{"buffer"},"\n"));

	}
	return @str;
    }
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

File::Tail - Perl extension for reading from continously updated files

=head1 SYNOPSIS

  use File::Tail;
  $file=File::Tail->new("/some/log/file");
  while (defined($line=$file->read)) {
      print "$line";
  }

  use File::Tail;
  $file=File::Tail->new(name=>$name, maxinterval=>300, adjustafter=>7);
  while (defined($line=$file->read)) {
      print "$line";
  }

OR, you could use tie (additional parameters can be passed with the name, or 
can be set using $ref):

    use File::Tail;
    my $ref=tie *FH,"File::Tail",(name=>$name);
    while (<FH>) {
        print "$_";
    }
}

Note that the above script will never exit. If there is nothing being written
to the file, it will simply block.

You can find more synopsii in the file logwatch, which is included
in the distribution.

=head1 DESCRIPTION

The primary purpose of File::Tail is reading and analysing log files while
they are being written, which is especialy usefull if you are monitoring
the logging process with a tool like Tobias Oetiker's MRTG.

The module tries very hard NOT to "busy-wait" on a file that has little 
traffic. Any time it reads new data from the file, it counts the number
of new lines, and divides that number by the time that passed since data
were last written to the file before that. That is considered the average
time before new data will be written. When there is no new data to read, 
C<File::Tail> sleeps for that number of seconds. Thereafter, the waiting 
time is recomputed dynamicaly. Note that C<File::Tail> never sleeps for
more than the number of seconds set by C<maxinterval>.

If the file does not get altered for a while, C<File::Tail> gets suspicious 
and startschecking if the file was truncated, or moved and recreated. If 
anything like that had happened, C<File::Tail> will quietly reopen the file,
and continue reading. The only way to affect what happens on reopen is by 
setting the reset_tail parameter (see below). The effect of this is that
the scripts need not be aware when the logfiles were rotated, they will
just quietly work on.

Note that the sleep and time used are from Time::HiRes, so this module
should do the right thing even if the time to sleep is less than one second.

The logwatch script (also included) demonstrates several ways of calling 
the methods.

=head1 CONSTRUCTOR

=head2 new ([ ARGS ]) 

Creates a C<File::Tail>. If it has only one paramter, it is assumed to 
be the filename. If the open fails, the module performs a croak. I
am currently looking for a way to set $! and return undef. 

You can pass several parameters to new:

=over 4

=item name

This is the name of the file to open. The file will be opened for reading.
This must be a regular file, not a pipe or a terminal (i.e. it must be
seekable).

=item maxinterval

The maximum number of seconds (real number) that will be spent sleeping.
Default is 60, meaning C<File::Tail> will never spend more than sixty
seconds without checking the file.

=item interval

The initial number of seconds (real number) that will be spent sleeping,
before the file is first checked. Default is ten seconds, meaning C<File::Tail>
will sleep for 10 seconds and then determine, how many new lines have appeared 
in the file.

=item adjustafter

The number of C<times> C<File::Tail> waits for the current interval,
before adjusting the interval upwards. The default is 10.

=item resetafter

The number of seconds after last change when C<File::Tail> decides 
the file may have been closed and reopened. The default is 
adjustafter*maxinterval.

=item nowait

Does not block on read, but returns an empty string if there is nothing
to read. DO NOT USE THIS unless you know what you are doing. If you 
are using it in a loop, you probably DON'T know what you are doing.
If you want to read tails from multiple files, use select.


=item ignore_nonexistant

    Do not complain if the file doesn't exist when it is first opened or
when it is to be reopened. (File may be reopened after resetafter seconds 
have passed since last data was found.)

=item tail
    When first started, read and return C<n> lines from the file. If C<n>
is zero, start at the end of file. If C<n> is negative, return the whole file.
    Default is C<0>.

=item reset_tail
    Same as tail, but applies after reset. (i.e. after the file has been
automaticaly closed and reopened). Defaults to C<-1>, i.e. does not skip 
any information present in the file when it first checks it. 

   Why would you want it otherwise? I've seen files which have been cycled
like this:
   grep -v lastmonth log >newlog
   mv log archive/lastmonth
   mv newlog log
   kill -HUP logger
  
   Obviously, if this happens and you have reset_tail set to c<-1>, you will
suddenly get a whole bunch of lines - lines you already saw. So in this case, 
reset_tail should probably be set to a small positive number or even C<0>.

=item debug

Set to nonzero if you want to see more about the inner workings of
File::Tail. Otherwise not useful.

=item errmode

Modeled after the methods from Net:Telnet, here you decide how the
errors should be handled. The parameter can be a code reference which
is called with the error string as a parameter, an array with a code
reference as the first parameter and other parameters to be passed to 
handler subroutine, or one of the words:

return  - ignore any error (just put error message in errmsg).
warn    - output the error message but continue
die     - display error message and exit

Default is die.

=back 

=head1 METHODS

=head2 read

C<read> returns one line from the input file. If there are no lines
ready, it blocks until there are.

=head1 TO BE DONE

The next version will support some form of "select" call, which will
make it possible to read from several File::Tail files at once, as well
as reading from sockets and File::Tail files without polling.

Also planned for 0.8: tail C<-n> functionality, using $/ instead of \n to
separate "lines" (which should make it possible to read wtmp type files).

Tests should be devised and put into test.pl.

=head1 AUTHOR

Matija Grabnar, matija.grabnar@arnes.si

=head1 SEE ALSO

perl(1), tail (1), 
MRTG 

(http://ee-staff.ethz.ch/~oetiker/webtools/mrtg/mrtg.html)

=cut

