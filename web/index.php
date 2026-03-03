<?php
// Entry point used by Apache/XAMPP when index.php is preferred.
// IMPORTANT: do not redirect from here. A redirect can cause an infinite loop
// when this file is copied into build/web and Apache picks index.php first.

$index = __DIR__ . DIRECTORY_SEPARATOR . 'index.html';
if (!is_file($index)) {
	http_response_code(404);
	header('Content-Type: text/plain; charset=utf-8');
	echo "Flutter web entry not found. Missing web/index.html\n";
	exit;
}

header('Content-Type: text/html; charset=utf-8');
readfile($index);
exit;
