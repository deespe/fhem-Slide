#####################################################################################
# $Id: 10_Slide.pm 18798 2019-03-05 19:13:28Z DeeSPe $
#
# Usage
#
# define <name> Slide <E-MAIL> <PASSWORD> [<INTERVAL>]
#
#####################################################################################

package main;

use strict;
use warnings;
use POSIX;
use JSON;
use HttpUtils;

my $version = "0.1.0";

sub Slide_Initialize($)
{
  my ($hash) = @_;
  #$hash->{AttrFn}       = "Slide_Attr";
  $hash->{DefFn}        = "Slide_Define";
  #$hash->{NotifyFn}     = "Slide_Notify";
  $hash->{GetFn}        = "Slide_Get";
  $hash->{SetFn}        = "Slide_Set";
  $hash->{UndefFn}      = "Slide_Undef";
  $hash->{AttrList}     = "disable:1,0 ".
                          "disabledForIntervals ".
                          "interval ".
                          $readingFnAttributes;
  $hash->{Clients}      = "SlideDevice";
}

sub Slide_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  my ($name,$type,$email,$sec,$int) = @args;
  return "Usage: define <name> Slide <E-MAIL> <PASSWORD> [<INTERVAL>]" if ($init_done && (@args < 4 || @args > 5));
  $int = 10 if ($int && $int < 10) ;
  $hash->{DEF} = "";
  $hash->{VERSION}    = $version;
  $hash->{NOTIFYDEV}  = "global";
  RemoveInternalTimer($hash);
  my $err = setKeyValue("Slide_".$name."_email",$email);
  return "not able to store e-mail address" if ($err);
  $err = setKeyValue("Slide_".$name."_sec",$sec);
  return "not able to store password" if ($err);
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{alias}     = "Slide";
    $attr{$name}{icon}      = "it_wifi";
    $attr{$name}{room}      = "Slide";
    $attr{$name}{interval}  = $int if ($int);
    readingsSingleUpdate($hash,"state","initialized",0);
  }
  return CommandSet(undef,"$name login");
}

sub Slide_Undef($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
  DevIo_CloseDev($hash);
  return;
}

sub Slide_Get($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  my ($err,$token) = getKeyValue("Slide_".$name."_token");
  Log3 $name,1,"$err - not able to get token" if ($err);
  my @par;
  if ($token)
  {
    push @par,"update:noArg";
    push @par,"household:noArg";
    push @par,"slides:noArg";
  }
  my $para = join(" ",@par);
  return "get $name needs one parameter: $para" if (!$cmd);
  if ($cmd eq "update")
  {
    CommandGet(undef,"$name household");
    CommandGet(undef,"$name slides");
    return undef;
  }
  elsif ($cmd eq "household")
  {
    return Slide_request($hash,"https://api.goslide.io/api/households","Slide_ParseHousehold");
  }
  elsif ($cmd eq "slides")
  {
    return Slide_request($hash,"https://api.goslide.io/api/slides/overview","Slide_ParseSlides");
  }
  else
  {
    return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
  }
}

sub Slide_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  my $value = (defined($args[0])) ? $args[0] : undef;
  return if (IsDisabled($name) && $cmd ne "?");
  return "\"set $name $cmd\" needs two arguments at maximum" if (@aa > 2);
  my ($err,$token) = getKeyValue("Slide_".$name."_token");
  Log3 $name,1,"$err - not able to get token" if ($err);
  my @par;
  push @par,"password";
  push @par,"login:noArg" if (!$token);
  push @par,"logout:noArg" if ($token);
  push @par,"holiday:0,1" if ($token);
  if ($cmd eq "password")
  {
    return "$cmd needs a value..." if (!$value);
    $err = setKeyValue("Slide_".$name."_sec",$value);
    if (!$err)
    {
      CommandSet(undef,"$name logout") if ($token);
      CommandSet(undef,"$name login");
      return undef;
    }
    return $err;
  }
  elsif ($cmd eq "login")
  {
    my ($erre,$email) = getKeyValue("Slide_".$name."_email");
    return "error reading e-mail address" if ($erre);
    my ($errp,$sec) = getKeyValue("Slide_".$name."_sec");
    return "error reading password" if ($errp);
    return Slide_request($hash,"https://api.goslide.io/api/auth/login","Slide_ParseLogin","{\"email\":\"$email\",\"password\": \"$sec\"}","POST");
  }
  elsif ($cmd eq "logout")
  {
    return Slide_request($hash,"https://api.goslide.io/api/auth/logout","Slide_ParseLogout",undef,"POST");
  }
  elsif ($cmd eq "holiday")
  {
    my $mode = $value ? "true" : "false";
    my $data = ReadingsVal($name,"household_holiday_routines","");
    # $data =~ s/"/\\"/g;
    $data = "{ \"holiday_mode\": $mode, \"data\": ".$data." }";
    # $data = "{ \\\"holiday_mode\\\": $mode, \\\"data\\\": ".$data." }";
    # $data =~ s/\\{2}/\\\\\\"/g;
    # Debug $data;
    return Slide_request($hash,"https://api.goslide.io/api/households/holiday_mode","Slide_ParseHoliday",$data,"POST");
  }
  my $para = join(" ",@par);
  return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
}

sub Slide_request($$$;$$)
{
  my ($hash,$url,$callback,$data,$method) = @_;
  $method = "GET" if (!$method);
  my $name = $hash->{NAME};
  my ($err,$token) = getKeyValue("Slide_".$name."_token");
  return "$err - not able to read token" if ($err);
  my $param = {
    url       => $url,
    timeout   => 5,
    hash      => $hash,
    method    => $method,
    header    => "Content-Type: application/json\r\nX-Requested-With: XMLHttpRequest",
    callback  => \&$callback
  };
  $param->{header} .= "\r\nAuthorization: ".ReadingsVal($name,".token_type","")." $token" if ($token);
  $param->{data} = $data if ($data);
  return HttpUtils_NonblockingGet($param);
}

sub Slide_ParseLogin($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    my $dec = eval {decode_json($data)};
    if ($dec->{access_token})
    {
      my $err = setKeyValue("Slide_".$name."_token",$dec->{access_token});
      return "$err - not able to store token" if ($err);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,".token_type",$dec->{token_type});
      readingsBulkUpdate($hash,".expires_at",$dec->{expires_at});
      readingsBulkUpdate($hash,".household_id",$dec->{household_id});
      readingsBulkUpdate($hash,"state","login successful");
      readingsEndUpdate($hash,1);
      CommandGet(undef,"$name update");
      return;
    }
    elsif ($dec->{message})
    {
      if ($dec->{message} eq "Unauthorized")
      {
        $err = "$dec->{message} - wrong e-mail address or wrong password";
        readingsSingleUpdate($hash,"state",$err,1);
        Log3 $name,1,"$name: $err";
      }
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub Slide_ParseLogout($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    my $dec = eval {decode_json($data)};
    if ($dec->{message})
    {
      readingsSingleUpdate($hash,"state",$dec->{message},1);
      if ($dec->{message} eq "Successfully logged out")
      {
        CommandDeleteReading(undef,"$name (\.token_type|\.expires_at|\.household_id|household_.*)");
        $err = setKeyValue("Slide_".$name."_token",undef);
        if ($err)
        {
          my $m = "$err - not able to delete token";
          Log3 $name,1,$m;
          return $m;
        }
      }
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub Slide_ParseHousehold($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
    CommandDeleteReading(undef,"$name household_.*");
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    my $dec = eval {decode_json($data)};
    $data = $dec->{data};
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"household_id",$data->{id});
    readingsBulkUpdate($hash,"household_name",$data->{name});
    readingsBulkUpdate($hash,"household_address",$data->{address});
    readingsBulkUpdate($hash,"household_lat",$data->{lat});
    readingsBulkUpdate($hash,"household_lon",$data->{lon});
    readingsBulkUpdate($hash,"household_xs_code",$data->{xs_code});
    readingsBulkUpdate($hash,"holiday",$data->{holiday_mode});
    readingsBulkUpdate($hash,"household_holiday_routines",encode_json($data->{holiday_routines}));
    readingsBulkUpdate($hash,"household_created_at",$data->{created_at});
    readingsBulkUpdate($hash,"household_updated_at",$data->{updated_at});
    readingsBulkUpdate($hash,"state","got household info");
    readingsEndUpdate($hash,1);
  }
}

sub Slide_ParseSlides($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
    # CommandDeleteReading(undef,"$name household_.*");
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    my $dec = eval {decode_json($data)};
    if ($dec->{slides})
    {
      my @slides = $dec->{slides};
      Dumper $dec->{slides} if (@slides > 0);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"state","got slides info");
      readingsEndUpdate($hash,1);
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub Slide_ParseHoliday($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
    # CommandDeleteReading(undef,"$name household_.*");
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    CommandGet(undef,"$name household");
    # my $dec = eval {decode_json($data)};
  }
}

1;

=pod
=item device
=item summary    control Slide devices
=item summary_DE Steuerung von Slide Ger&auml;ten
=begin html

<a name="Slide"></a>
<h3>Slide</h3>
<ul>
  With <i>Slide</i> you are able to control Slide devices.<br>
  <br>
  <a name="Slide_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Slide &lt;E-MAIL&gt; &lt;PASSWORD&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Example for running Slide:
  <br><br>
  <ul>
    <code>define sl Slide jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  If you have homebridgeMapping in your attributes an appropriate mapping will be added, genericDeviceType as well.
  <br>
  <a name="Slide_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      set device password
    </li>
  </ul>  
  <br>
  <a name="Slide_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      get status update
    </li>
  </ul>
  <br>
  <a name="Slide_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      stop polling and disable device completely<br>
      default: 0
    </li>
  </ul>
  <br>
  <a name="Slide_read"></a>
  <p><b>Readings</b></p>
  <p>All readings updates will create events.</p>
  <ul>
    <li>
      <i>state</i><br>
      current state
    </li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="Slide"></a>
<h3>Slide</h3>
<ul>
  Mit <i>Slide</i> k&ouml;nnen Slide Ger&auml;te gesteuert werden.<br>
  <br>
  <a name="Slide_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Slide &lt;E-MAIL&gt; &lt;PASSWORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Beispiel f&uuml;r:
  <br><br>
  <ul>
    <code>define sl Slide jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  Wenn homebridgeMapping in der Attributliste ist, so wird ein entsprechendes Mapping hinzugef&uuml;gt, ebenso genericDeviceType.
  <br>
  <a name="Slide_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      Passwort des Ger&auml;tes setzen
    </li>
  </ul>  
  <br>
  <a name="Slide_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      Status Update abrufen
    </li>
  </ul>
  <br>
  <a name="Slide_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      Anhalten der automatischen Abfrage und komplett deaktivieren<br>
      Voreinstellung: 0
    </li>
  </ul>
  <br>
  <a name="Slide_read"></a>
  <p><b>Readings</b></p>
  <p>Alle Aktualisierungen der Readings erzeugen Events.</p>
  <ul>
    <li>
      <i>state</i><br>
      aktueller Zustand
    </li>
  </ul>
</ul>

=end html_DE
=cut
