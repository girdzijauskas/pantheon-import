#!/usr/local/bin/php
<?php

$dir = $argv[2];

$file_location = './' . $dir . '/composer.json';


$json =  file_get_contents($file_location);

$json_data = json_decode($json, true);

$json_data['require-dev'] = new stdClass();
$json_data['scripts'] = new stdClass();

$final_json = json_encode($json_data, JSON_PRETTY_PRINT);

$fp = fopen($file_location, 'w');

fwrite($fp, $final_json);

fclose($fp);
