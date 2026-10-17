<?php
/**
 * fan-imagehost 内置服务器路由器
 *
 * 仅用于 `php -S` 运行方式（systemd / 一键脚本安装）。
 * PHP 内置服务器不解析 .htaccess，这里等价实现原程序在 Apache/Nginx 下的安全策略：
 *   1. 禁止直接执行 /i/ 与 /public/ 目录下的 .php（防上传 WebShell，对应原目录 .htaccess）
 *   2. 禁止直接访问 /config、/scripts 等内部目录与工程文件
 * 其余请求返回 false，交还内置服务器原生处理（静态文件、各目录 index.php 均正常）。
 */

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

// 1) 镜像 i/ 与 public/ 的 .htaccess: <Files ~ ".php"> Deny
if (preg_match('#^/(i|public)/.*\.php$#i', $uri)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Forbidden';
    return true;
}

// 2) 内部目录与工程文件
$segments = explode('/', trim($uri, '/'));
$first = strtolower($segments[0] ?? '');

if ($first !== '' && in_array($first, array('config', 'scripts', 'docker'), true)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Forbidden';
    return true;
}

if (preg_match('#^/(router\.php|Dockerfile|docker-compose\.yml|\.dockerignore|\.gitignore|\.whitesource)$#i', $uri)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Forbidden';
    return true;
}

return false;
