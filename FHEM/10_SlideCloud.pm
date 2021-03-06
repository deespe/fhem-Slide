#####################################################################################
# $Id: 10_SlideCloud.pm 18798 2019-03-05 19:13:28Z DeeSPe $
#
# Usage
#
# define <name> SlideCloud <E-MAIL> <PASSWORD> [<INTERVAL>]
#
#####################################################################################

package main;

use strict;
use warnings;
use POSIX;
use JSON;
use HttpUtils;

my $version = "0.1.0";

sub SlideCloud_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}       = "SlideCloud_Attr";
  $hash->{DefFn}        = "SlideCloud_Define";
  $hash->{NotifyFn}     = "SlideCloud_Notify";
  $hash->{GetFn}        = "SlideCloud_Get";
  $hash->{SetFn}        = "SlideCloud_Set";
  $hash->{RenameFn}     = "SlideCloud_Rename";
  $hash->{CopyFn}       = "SlideCloud_Copy";
  $hash->{UndefFn}      = "SlideCloud_Undef";
  $hash->{DeleteFn}     = "SlideCloud_Delete";
  $hash->{ReadFn}       = "SlideCloud_Read";
  $hash->{WriteFn}      = "SlideCloud_Write";
  $hash->{Clients}      = ":Slide:";
  $hash->{AttrList}     = "disable:1,0 ".
                          "disabledForIntervals ".
                          "interval ".
                          $readingFnAttributes;
  foreach (sort keys %{$modules{SlideCloud}{defptr}})
  {
    my $hash = $modules{SlideCloud}{defptr}{$_};
    $hash->{VERSION} = $version;
  }
}

sub SlideCloud_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  my ($name,$type,$email,$sec,$int) = @args;
  return "Usage: define <name> SlideCloud <E-MAIL> <PASSWORD> [<INTERVAL>]" if ($init_done && (@args < 4 || @args > 5));
  $int = 10 if ($int && $int < 10) ;
  $hash->{DEF}        = "";
  $hash->{BRIDGE}     = 1;
  $hash->{VERSION}    = $version;
  $hash->{NOTIFYDEV}  = "global";
  RemoveInternalTimer($hash);
  if ($init_done && !defined $hash->{OLDDEF})
  {
    my $msg;
    my $err = SlideCloud_storeVal("SlideCloud_".$name."_email",$email);
    $msg = "not able to store e-mail address ($err) " if ($err);
    $err = SlideCloud_storeVal("SlideCloud_".$name."_sec",$sec);
    $msg .= "not able to store password ($err)" if ($err);
    return $msg if ($msg);
    $attr{$name}{alias}       = "Slide Cloud API";
    $attr{$name}{icon}        = "file_json-ld1";
    $attr{$name}{interval}    = $int if ($int);
    $attr{$name}{room}        = "Slide";
    $attr{$name}{webCmd}      = "holiday_mode";
    $attr{$name}{webCmdLabel} = "Holiday Mode";
    readingsSingleUpdate($hash,"state","initialized",0);
    CommandSet(undef,"$name login") if (!IsDisabled($name));
  }
  return;
}

sub SlideCloud_Undef($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  return;
}

sub SlideCloud_Rename($$)
{
  my ($nname,$oname) = @_;
  my (undef,$token) = SlideCloud_retriveVal("SlideCloud_".$oname."_token");
  my (undef,$email) = SlideCloud_retriveVal("SlideCloud_".$oname."_email");
  my (undef,$sec) = SlideCloud_retriveVal("SlideCloud_".$oname."_sec");
  if ($token)
  {
    SlideCloud_storeVal("SlideCloud_".$oname."_token",undef);
    SlideCloud_storeVal("SlideCloud_".$nname."_token",$token);
  }
  if ($email)
  {
    SlideCloud_storeVal("SlideCloud_".$oname."_email",undef);
    SlideCloud_storeVal("SlideCloud_".$nname."_email",$email);
  }
  if ($sec)
  {
    SlideCloud_storeVal("SlideCloud_".$oname."_sec",undef);
    SlideCloud_storeVal("SlideCloud_".$nname."_sec",$sec);
  }
}

sub SlideCloud_Delete($$)
{
  my ($hash,$arg) = @_;
  my $name = $hash->{NAME};
  my ($err,$token) = SlideCloud_retriveVal("SlideCloud_".$name."_token");
  CommandSet(undef,"$name logout") if ($token);
  SlideCloud_storeVal("SlideCloud_".$name."_email",undef);
  SlideCloud_storeVal("SlideCloud_".$name."_sec",undef);
  return;
}

sub SlideCloud_Get($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  my ($err,$token) = SlideCloud_retriveVal("SlideCloud_".$name."_token");
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
  if (lc $cmd eq "update")
  {
    CommandGet(undef,"$name household");
    CommandGet(undef,"$name slides");
    return undef;
  }
  elsif (lc $cmd eq "household")
  {
    return SlideCloud_request($hash,"https://api.goslide.io/api/households","SlideCloud_ParseHousehold");
  }
  elsif (lc $cmd eq "slides")
  {
    return SlideCloud_request($hash,"https://api.goslide.io/api/slides/overview","SlideCloud_ParseSlides");
  }
  else
  {
    return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
  }
}

sub SlideCloud_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  $cmd = lc $cmd;
  my $value = (defined($args[0])) ? $args[0] : undef;
  return if (IsDisabled($name) && $cmd ne "?");
  return "\"set $name $cmd\" needs two arguments at maximum" if (@aa > 2);
  my ($err,$token) = SlideCloud_retriveVal("SlideCloud_".$name."_token");
  Log3 $name,1,"$err - not able to get token" if ($err);
  my @par;
  push @par,"email";
  push @par,"password";
  push @par,"login:noArg" if (!$token);
  if ($token)
  {
    push @par,"logout:noArg";
    push @par,"holiday_mode:on,off";
    push @par,"autocreate:noArg";
  }
  if ($cmd =~ /^password|email$/)
  {
    return "set $cmd needs a value..." if (!$value);
    $err = "";
    $err .= SlideCloud_storeVal("SlideCloud_".$name."_email",$value) if ($cmd eq "email");
    $err .= " " if ($err);
    $err .= SlideCloud_storeVal("SlideCloud_".$name."_sec",$value) if ($cmd eq "password");
    if (!$err)
    {
      CommandSet(undef,"$name logout") if ($token);
      return undef;
    }
    Log3 $name,1,$err;
    return $err;
  }
  elsif ($cmd eq "login")
  {
    my ($erre,$email) = SlideCloud_retriveVal("SlideCloud_".$name."_email");
    Log3 $name,1,"$name: error reading e-mail address" if ($erre);
    Log3 $name,1,"$name: error no e-mail address found, please set it" if (!$email);
    my ($errp,$sec) = SlideCloud_retriveVal("SlideCloud_".$name."_sec");
    Log3 $name,1,"$name: error reading password" if ($errp);
    Log3 $name,1,"$name: error no password found, please set it" if (!$sec);
    readingsSingleUpdate($hash,"state","an error occured, please see the log",1) if ($erre || $errp || !$email || !$sec);
    return SlideCloud_request($hash,"https://api.goslide.io/api/auth/login","SlideCloud_ParseLogin","{\"email\":\"$email\",\"password\": \"$sec\"}","POST");
  }
  elsif ($cmd eq "logout")
  {
    return SlideCloud_request($hash,"https://api.goslide.io/api/auth/logout","SlideCloud_ParseLogout",undef,"POST");
  }
  elsif ($cmd eq "autocreate")
  {
    return "not implemented yet";
  }
  elsif ($cmd eq "holiday_mode")
  {
    my $mode = $value eq "on" ? "true" : "false";
    my $data = ReadingsVal($name,"holiday_routines",undef);
    return "no holiday data available, please execute \"get $name household\" and after that try to set holiday_mode again"  if (!$data || $data eq "null");
    $data = "{ \"holiday_mode\": $mode, \"data\": ".$data." }";
    Log3 $name,5,"$name: $data";
    return SlideCloud_request($hash,"https://api.goslide.io/api/households/holiday_mode","SlideCloud_ParseHoliday",$data,"POST");
  }
  my $para = join(" ",@par);
  return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
}

sub SlideCloud_request($$$;$$)
{
  my ($hash,$url,$callback,$data,$method) = @_;
  $method = "GET" if (!$method);
  my $name = $hash->{NAME};
  if (IsDisabled($name))
  {
    readingsSingleUpdateIfChanged($hash,"state","inactive",1);
    return undef;
  }
  my ($err,$token) = SlideCloud_retriveVal("SlideCloud_".$name."_token");
  return "$err - not able to read token" if ($err);
  my $param = {
    url       => $url,
    timeout   => 5,
    hash      => $hash,
    method    => $method,
    header    => "Content-Type: application/json\r\nX-Requested-With: XMLHttpRequest",
    callback  => \&$callback
  };
  $param->{header} .= "\r\nAuthorization: ".ReadingsVal($name,".token_type","Bearer")." $token" if ($token);
  $param->{data} = $data if ($data);
  return HttpUtils_NonblockingGet($param);
}

sub SlideCloud_ParseLogin($)
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
    my $decoded = eval {decode_json($data)};
    if ($decoded->{access_token})
    {
      my $err = SlideCloud_storeVal("SlideCloud_".$name."_token",$decoded->{access_token});
      return "$err - not able to store token" if ($err);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,".token_type",$decoded->{token_type});
      readingsBulkUpdate($hash,".expires_at",$decoded->{expires_at});
      readingsBulkUpdate($hash,"state","login successful");
      readingsEndUpdate($hash,1);
      CommandGet(undef,"$name update");
      return;
    }
    elsif ($decoded->{message})
    {
      $err = $decoded->{message};
      $err .= " - wrong e-mail address or wrong password" if (!$decoded->{errors});
      $err .= " ".$decoded->{errors}->{email}[0] if ($decoded->{errors}->{email}[0]);
      $err .= " ".$decoded->{errors}->{password}[0] if ($decoded->{errors}->{password}[0]);
      readingsSingleUpdate($hash,"state",$err,1);
      Log3 $name,1,"$name: $err";
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub SlideCloud_ParseLogout($)
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
    my $decoded = eval {decode_json($data)};
    if ($decoded->{message})
    {
      if ($decoded->{message} =~ /^(Successfully.logged.out|Unauthenticated.)$/)
      {
        CommandDeleteReading(undef,"$name .*");
        $err = SlideCloud_storeVal("SlideCloud_".$name."_token",undef);
        if ($err)
        {
          my $m = "$err - not able to delete token";
          Log3 $name,1,$m;
          return $m;
        }
        readingsSingleUpdate($hash,"state","ERROR - Successfully logged out",1);
      }
      else
      {
        readingsSingleUpdate($hash,"state","ERROR - ".$decoded->{message},1);
      }
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub SlideCloud_ParseHousehold($)
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    CommandDeleteReading(undef,"$name (id|name|address|lat|lon|xs_code|holiday_mode|holiday_routines|created_at|updated_at)");
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
  }
  elsif ($data)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $data";
    my $decoded = eval {decode_json($data)};
    readingsBeginUpdate($hash);
    if ($decoded->{data})
    {
      $data = $decoded->{data};
      readingsBulkUpdate($hash,"id",$data->{id});
      readingsBulkUpdate($hash,"name",$data->{name});
      readingsBulkUpdate($hash,"address",$data->{address});
      readingsBulkUpdate($hash,"lat",$data->{lat});
      readingsBulkUpdate($hash,"lon",$data->{lon});
      readingsBulkUpdate($hash,"xs_code",$data->{xs_code});
      readingsBulkUpdate($hash,"holiday_mode",$data->{holiday_mode} ? "on" : "off");
      readingsBulkUpdate($hash,"holiday_routines",encode_json($data->{holiday_routines}));
      readingsBulkUpdate($hash,"created_at",$data->{created_at});
      readingsBulkUpdate($hash,"updated_at",$data->{updated_at});
      readingsBulkUpdate($hash,"state","Got household info");
    }
    elsif ($decoded->{message})
    {
      readingsBulkUpdate($hash,"state","ERROR - ".$decoded->{message});
    }
    else
    {
      readingsBulkUpdate($hash,"state","ERROR - unknown error");
    }
    readingsEndUpdate($hash,1);
  }
}

sub SlideCloud_ParseSlides($)
{
  my ($param,$err,$json) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
  }
  elsif ($json)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $json";
    my $decoded = eval {decode_json($json)};
    if ($decoded->{slides})
    {
      my @slides = @{$decoded->{slides}};
      my $msg = "Got Slides info";
      if (@slides)
      {
        foreach (@slides)
        {
          my $cid     = $_->{id};
          my $cname   = $_->{device_name};
          my $ctype   = $_->{curtain_type};
          my $did     = $_->{device_id};
          my $hid     = $_->{household_id};
          my $zid     = $_->{zone_id};
          my $tg      = $_->{touch_go};
          my $pos     = $_->{device_info}->{pos};
          my @rou     = @{$_->{routines}};
          Debug "cid: $cid, cname: $cname, ctype: $ctype, did: $did, hid: $hid, zid: $zid, tg: $tg, pos: $pos";
          foreach my $r (@rou)
          {
            Debug "id: ".$r->{id}.", action: ".$r->{action}.", at: ".$r->{at}.", enable: ".$r->{enable}.", offset: ".$r->{payload}->{offset}.", pos: ".$r->{payload}->{pos};
          }
        }
      }
      elsif (ref($decoded->{slides}[0]) ne "HASH")
      {
        $msg = "No Slides found";
      }
      else
      {
        $msg = "ERROR - Unknown error";
      }
      readingsSingleUpdate($hash,"state",$msg,1);
    }
    elsif ($decoded->{message})
    {
      readingsSingleUpdate($hash,"state","ERROR - ".$decoded->{message},1);
    }
    else
    {
      readingsSingleUpdate($hash,"state","ERROR - unknown error",1);
    }
  }
}

sub SlideCloud_ParseHoliday($)
{
  my ($param,$err,$json) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,3,"error while requesting ".$param->{url}." - $err";
    readingsSingleUpdate($hash,"state","ERROR - $err",1);
  }
  elsif ($json)
  {
    Log3 $name,5,"url ".$param->{url}." returned: $json";
    CommandGet(undef,"$name household");
  }
}

sub SlideCloud_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  my $err;
  if ($cmd eq "set")
  {
    if ($attr_name eq "disabled")
    {
      $err = "must be 1 to disable or delete the attribute to enable" if ($attr_value !~ /^1$/);
    }
    elsif ($attr_name eq "disabledForIntervals")
    {
    }
    elsif ($attr_name eq "interval")
    {
      $err = "must be an integer (<=86400) for seconds" if ($attr_value !~ /^(\d{1,5})$/ || $1 > 86400);
    }
  }
  else
  {
    #
  }
  return $err ? $err : undef;
}

sub SlideCloud_Notify($$)
{

  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  if (IsDisabled($name))
  {
    readingsSingleUpdateIfChanged($hash,"state","inactive",1);
    return undef;
  }
  my $devname = $dev->{NAME};
  my $devtype = $dev->{TYPE};
  return if ($devname ne "global");
  return if (!grep(/^INITIALIZED|REREADCFG$/,@{$dev->{CHANGED}}));
  my $events  = deviceEvents( $dev, 1 );
  return if (!$events);
  return;
}

sub SlideCloud_autocreate($;$)
{
  my ($hash,$force)= @_;
  my $name = $hash->{NAME};
  if (!$force)
  {
    foreach my $d (keys %defs)
    {
      next if ($defs{$d}{TYPE} ne "autocreate");
      return undef if (AttrVal($defs{$d}{NAME},"disable",undef));
    }
  }
  my $autocreated = 0;


  
  if ($autocreated)
  {
    Log3 $name, 2, "$name: autocreated $autocreated devices";
    CommandSave(undef,undef) if (AttrVal("autocreate","autosave",1));
  }
  return "created $autocreated devices";
}

sub SlideCloud_dispatch($$$;$)
{
  my ($param,$err,$data,$json) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  if ($err)
  {
    Log3 $name,2,"$name: http request failed: $err";
  }
  elsif ($data || $json)
  {
    if (!$data && !$json)
    {
      Log3 $name,2,"$name: empty answer received";
      return undef;
    }
    elsif ($data && $data !~ m/^[\[{].*[\]}]$/ )
    {
      Log3 $name,2,"$name: invalid json detected: $data";
      return undef;
    }
    my $queryAfterSet = AttrVal($name,"queryAfterSet",1);
    if (!$json)
    {
      $json = eval { decode_json($data) };
      Log3 $name,2,"$name: json error: $@ in $data" if ($@);
    }
    return undef if (!$json);
    my $type = $param->{type};
  }
}

sub SlideCloud_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return;
}

sub SlideCloud_Write($)
{
  my ($hash,$chash,$name,$id,$obj) = @_;
  return;
}

sub SlideCloud_storeVal($$)
{
  my ($key,$val) = @_;
  my $err = setKeyValue($key,$val);
  return $err ? $err : undef;
}

sub SlideCloud_retriveVal($)
{
  my ($key) = @_;
  my ($err,$val) = getKeyValue($key);
  return ($err,$val);
}

1;

=pod
=item device
=item summary    control Slide devices over cloud API
=item summary_DE Steuerung von Slide Ger&auml;ten &uuml;ber Cloud API
=begin html

<a name="SlideCloud"></a>
<h3>SlideCloud</h3>
<ul>
  With <i>SlideCloud</i> you are able to control Slide devices.<br>
  <br>
  <a name="SlideCloud_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; SlideCloud &lt;E-MAIL&gt; &lt;PASSWORD&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Example for running SlideCloud:
  <br><br>
  <ul>
    <code>define slc SlideCloud jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  If you have homebridgeMapping in your attributes an appropriate mapping will be added, genericDeviceType as well.
  <br>
  <a name="SlideCloud_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      set device password
    </li>
  </ul>  
  <br>
  <a name="SlideCloud_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      get status update
    </li>
  </ul>
  <br>
  <a name="SlideCloud_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      stop polling and disable device completely<br>
      default: 0
    </li>
  </ul>
  <br>
  <a name="SlideCloud_read"></a>
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

<a name="SlideCloud"></a>
<h3>SlideCloud</h3>
<ul>
  Mit <i>SlideCloud</i> k&ouml;nnen Slide Ger&auml;te gesteuert werden.<br>
  <br>
  <a name="SlideCloud_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; SlideCloud &lt;E-MAIL&gt; &lt;PASSWORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Beispiel f&uuml;r:
  <br><br>
  <ul>
    <code>define slc SlideCloud jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  Wenn homebridgeMapping in der Attributliste ist, so wird ein entsprechendes Mapping hinzugef&uuml;gt, ebenso genericDeviceType.
  <br>
  <a name="SlideCloud_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      Passwort des Ger&auml;tes setzen
    </li>
  </ul>  
  <br>
  <a name="SlideCloud_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      Status Update abrufen
    </li>
  </ul>
  <br>
  <a name="SlideCloud_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      Anhalten der automatischen Abfrage und komplett deaktivieren<br>
      Voreinstellung: 0
    </li>
  </ul>
  <br>
  <a name="SlideCloud_read"></a>
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
