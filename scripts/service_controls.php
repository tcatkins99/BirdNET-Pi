<?php 
function service_status($name) {
  $user = shell_exec("awk -F: '/1000/{print $1}' /etc/passwd");
  $home = shell_exec("awk -F: '/1000/{print $6}' /etc/passwd");
  $home = trim($home);

  if($name == "birdnet_server.service") {
    $filesinproc=trim(shell_exec("ls ".$home."/BirdSongs/Processed | wc -l"));
    if($filesinproc > 200) { 
       echo "<span style='color:#fc6603'>(stalled - backlog of ".$filesinproc." files in ~/BirdSongs/Processed/)</span>";
       return;
    }
  } 
  $op = shell_exec("sudo systemctl status ".$name." | grep Active | grep ' active\| activating\|running\|waiting\|start'");
  if(strlen($op) > 0) {
    echo "<span style='color:green'>(active)</span>";
  } else {
    echo "<span style='color:#fc6603'>(inactive)</span>";
  }
}
?>
<html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<br>
<div class="servicecontrols">
  <form action="" method="GET">
    <h3>Live Audio Stream <?php echo service_status("livestream.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop livestream.service && sudo systemctl stop icecast2.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart livestream.service && sudo systemctl restart icecast2.service">Restart </button>
    <button type="submit" name="submit" value="sudo systemctl disable --now livestream.service && sudo systemctl disable icecast2 && sudo systemctl stop icecast2.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable icecast2 && sudo systemctl start icecast2.service && sudo systemctl enable --now livestream.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Web Terminal <?php echo service_status("web_terminal.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop web_terminal.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart web_terminal.service">Restart </button>
    <button type="submit" name="submit" value="sudo systemctl disable --now web_terminal.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now web_terminal.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>BirdNET Log <?php echo service_status("birdnet_log.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop birdnet_log.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart birdnet_log.service">Restart </button>
    <button type="submit" name="submit" value="sudo systemctl disable --now birdnet_log.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now birdnet_log.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Extraction Service <?php echo service_status("extraction.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop extraction.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart extraction.service">Restart </button>
    <button type="submit" name="submit" value="sudo systemctl disable --now extraction.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now extraction.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>BirdNET Analysis Server <?php echo service_status("birdnet_server.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop birdnet_server.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart birdnet_server.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now birdnet_server.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now birdnet_server.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>BirdNET Analysis Client <?php echo service_status("birdnet_analysis.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop birdnet_analysis.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart birdnet_analysis.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now birdnet_analysis.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now birdnet_analysis.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Streamlit Statistics <?php echo service_status("birdnet_stats.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop birdnet_stats.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart birdnet_stats.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now birdnet_stats.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now birdnet_stats.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Recording Service <?php echo service_status("birdnet_recording.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop birdnet_recording.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart birdnet_recording.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now birdnet_recording.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now birdnet_recording.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Chart Viewer <?php echo service_status("chart_viewer.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop chart_viewer.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart chart_viewer.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now chart_viewer.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now chart_viewer.service">Enable</button>
  </form>
  <form action="" method="GET">
    <h3>Spectrogram Viewer <?php echo service_status("spectrogram_viewer.service");?></h3>
    <button type="submit" name="submit" value="sudo systemctl stop spectrogram_viewer.service">Stop</button>
    <button type="submit" name="submit" value="sudo systemctl restart spectrogram_viewer.service">Restart</button>
    <button type="submit" name="submit" value="sudo systemctl disable --now spectrogram_viewer.service">Disable</button>
    <button type="submit" name="submit" value="sudo systemctl enable --now spectrogram_viewer.service">Enable</button>
  </form>
  <form action="" method="GET">
    <button type="submit" name="submit" value="stop_core_services.sh">Stop Core Services</button>
  </form> 
  <form action="" method="GET">
    <button type="submit" name="submit" value="restart_services.sh">Restart Core Services</button>
  </form> 
</div>
