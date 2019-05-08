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
                          "email ".
                          "interval ".
                          "password ".
                          $readingFnAttributes;
}

sub Slide_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  my ($name,$type,$email,$sec,$int) = @args;
  return "Usage: define <name> Slide <E-MAIL> <PASSWORD> [<INTERVAL>]" if ($init_done && (@args < 4 || @args > 5));
  $int = 10 if ($int && $int < 10) ;
  $hash->{VERSION}    = $version;
  $hash->{NOTIFYDEV}  = "global";
  RemoveInternalTimer($hash);
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{alias}     = "Slide";
    $attr{$name}{email}     = $email;
    $attr{$name}{icon}      = "it_wifi";
    $attr{$name}{password}  = $sec;
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
  my @par;
  if (ReadingsVal($name,".access_token",undef))
  {
    push @par,"update:noArg";
    push @par,"household:noArg";
    push @par,"slides:noArg";
  }
  my $para = join(" ",@par);
  return "get $name needs one parameter: $para" if (!$cmd);
  if ($cmd eq "update")
  {
    return "$cmd not implemented yet...";
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
    return $para?"Unknown argument $cmd for $name, choose one of $para":undef;
  }
}

sub Slide_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  return "\"set $name $cmd\" needs two arguments at maximum" if (@aa > 2);
  my @par;
  push @par,"password";
  push @par,"login:noArg" if (!ReadingsVal($name,".access_token",undef));
  push @par,"logout:noArg" if (ReadingsVal($name,".access_token",undef));
  my $para = join(" ",@par);
  if ($cmd eq "password")
  {
    return "$cmd not implemented yet...";
  }
  elsif ($cmd eq "login")
  {
    return Slide_request($hash,"https://api.goslide.io/api/auth/login","Slide_ParseLogin","{\"email\":\"".AttrVal($name,"email","")."\",\"password\": \"".AttrVal($name,"password","")."\"}","POST");
  }
  elsif ($cmd eq "logout")
  {
    return Slide_request($hash,"https://api.goslide.io/api/auth/logout","Slide_ParseLogout",undef,"POST");
  }
  return $para;
}

sub Slide_request($$$;$$)
{
  my ($hash,$url,$callback,$data,$method) = @_;
  $method = "GET" if (!$method);
  my $name = $hash->{NAME};
  my $param = {
    url       => $url,
    timeout   => 5,
    hash      => $hash,
    method    => $method,
    header    => "Content-Type: application/json\r\nX-Requested-With: XMLHttpRequest",
    callback  => \&$callback
  };
  $param->{header} .= "\r\nAuthorization: ".ReadingsVal($name,".token_type","")." ".ReadingsVal($name,".access_token","") if (ReadingsVal($name,".access_token",undef));
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
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,".access_token",$dec->{access_token});
      readingsBulkUpdate($hash,".token_type",$dec->{token_type});
      readingsBulkUpdate($hash,".expires_at",$dec->{expires_at});
      readingsBulkUpdate($hash,".household_id",$dec->{household_id});
      readingsBulkUpdate($hash,"state","login successful");
      readingsEndUpdate($hash,1);
      CommandGet(undef,"$name household");
      CommandGet(undef,"$name slides");
      return;
    }
    elsif ($dec->{message})
    {
      readingsSingleUpdate($hash,"state",$dec->{message},1);
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
    CommandDeleteReading(undef,"$name \.(access_token|token_type|expires_at|household_id)");
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
      CommandDeleteReading(undef,"$name \.(access_token|token_type|expires_at|household_id)") if ($dec->{message} eq "Successfully logged out");
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
    readingsBulkUpdate($hash,"household_holiday_mode",$data->{holiday_mode});
    readingsBulkUpdate($hash,"household_holiday_routines",$data->{holiday_routines});
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
