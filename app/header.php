<!DOCTYPE html>
<html lang="zh-cn">
<?php require_once __DIR__ . '/function.php'; ?>

<head>
	<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
	<meta http-equiv="X-UA-Compatible" content="IE=edge">
	<meta name="renderer" content="webkit" />
	<meta name="force-rendering" content="webkit" />
	<meta name="author" content="fan-imagehost">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title><?php echo $config['title']; ?></title>
	<meta name="keywords" content="<?php echo $config['keywords']; ?>" />
	<meta name="description" content="<?php echo $config['description']; ?>" />
	<link rel="shortcut icon" type="image/x-icon" href="<?php static_cdn(); ?>/favicon.ico" />
	<link rel="apple-touch-icon" href="<?php static_cdn(); ?>/apple-touch-icon.png" />
	<link rel="stylesheet" href="<?php static_cdn(); ?>/public/static/zui/css/zui.min.css">
	<link rel="stylesheet" href="<?php static_cdn(); ?>/public/static/nprogress/nprogress.min.css">
	<link rel="stylesheet" href="<?php static_cdn(); ?>/public/static/zui/theme/zui-theme-<?php echo $config['theme']; ?>.css">
	<script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/lib/jquery/jquery-3.6.4.min.js"></script>
	<script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/js/zui.min.js"></script>
	<!--[if lt IE 9]>
    <script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/lib/ieonly/html5shiv.js"></script>
    <script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/lib/ieonly/respond.js"></script>
    <script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/lib/ieonly/excanvas.js"></script>
  	<![endif]-->
 	<?php /** 页头自定义代码 */ echo $config['customize']; ?>
	<style>
		/* Splash screen */
		#splash-screen {
			position: fixed;
			top: 0;
			left: 0;
			width: 100%;
			height: 100%;
			background: #ffffff;
			z-index: 9999;
			display: flex;
			align-items: center;
			justify-content: center;
			transition: opacity 0.5s ease;
			pointer-events: none;
		}

		#splash-screen.splash-hidden {
			opacity: 0;
		}

		#splash-screen img {
			width: 120px;
			height: 120px;
			animation: splash-pulse 1.2s ease-in-out infinite;
			user-select: none;
			-webkit-user-drag: none;
		}

		@keyframes splash-pulse {
			0% {
				transform: scale(0.9);
				opacity: 0.8;
			}
			50% {
				transform: scale(1);
				opacity: 1;
			}
			100% {
				transform: scale(0.9);
				opacity: 0.8;
			}
		}

		@media (prefers-color-scheme: dark) {
			#splash-screen {
				background: #1f1f1f;
			}
		}
	</style>
</head>

<body class="container">
	<?php if (isset($isIndex) && $isIndex): ?>
	<div id="splash-screen">
		<img src="<?php static_cdn(); ?>/public/images/fan-imagehost.svg" alt="fan-imagehost">
	</div>
	<?php endif; ?>
	<div class="page-header">
		<div class="navbar-header">
			<button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".navbar-collapse-fan-imagehost">
				<span class="icon icon-bars"></span>
			</button>
		</div>
		<div class="collapse navbar-collapse navbar-collapse-fan-imagehost">
			<ul class="nav nav-pills">
				<li><a href="<?php echo $config['domain']; ?>"><i class="icon icon-home"></i> 首页</a></li>
				<?php /** 非管理或未开启不显示广场 */ if ($config['showSwitch'] || is_who_login('admin')) : ?>
					<li><a href="<?php echo $config['domain']; ?>/app/list.php"><i class="icon icon-th"></i> 广场<span class="label label-badge label-primary"><?php echo get_file_by_glob(APP_ROOT . config_path(), 'number'); ?></span></a></li>
				<?php endif; ?>
				<?php /** 非管理或未开启不显示上传历史 */ if ($config['history'] || is_who_login('admin')) : ?>
					<li><a href="<?php echo $config['domain']; ?>/app/history.php"><i class="icon icon-history"></i> 历史<span class="label label-badge label-primary"></span></a></li>
				<?php endif; ?>
				<?php /** 非管理不显示设置 */ if (is_who_login('admin')) : ?>
					<li><a href="<?php echo $config['domain']; ?>/admin/admin.inc.php"><i class="icon icon-cogs"></i> 设置</a></li>
				<?php endif; ?>
				<?php /** 非管理或未开启不显示统计 */ if ($config['chart_on'] && is_who_login('admin')) : ?>
					<li><a href="<?php echo $config['domain']; ?>/admin/chart.php"><i class="icon icon-pie-chart"></i> 统计</a></li>
				<?php endif; ?>
				<?php /** 账号登录 */ if (is_who_login('status')) : ?>
					<!-- 右侧的导航项目 -->
					<li class="nav navbar-nav navbar-right hidden-xs"><a href="<?php echo $config['domain']; ?>/admin/index.php?login=logout">您好：<?php echo json_decode($_COOKIE['auth'])[0]; ?> <i class="icon icon-signout"></i></a></li>
				<?php else : ?>
					<li class="nav navbar-nav navbar-right hidden-xs"><a href="<?php echo $config['domain']; ?>/admin/index.php"><i class="icon icon-user"> 登录</i></a></li>
				<?php endif; ?>
			</ul>
		</div>
	</div>
	<!-- 顶部导航栏END -->