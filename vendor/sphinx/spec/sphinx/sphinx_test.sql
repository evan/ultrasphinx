/*
SQLyog Enterprise - MySQL GUI v5.20
Host - 5.0.27-community-nt : Database - sphinx_test
*********************************************************************
Server version : 5.0.27-community-nt
*/

SET NAMES utf8;

SET SQL_MODE='';

create database if not exists `sphinx_test`;

USE `sphinx_test`;

/*Table structure for table `links` */

DROP TABLE IF EXISTS `links`;

CREATE TABLE `links` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `description` text,
  `group_id` int(11) NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

/*Data for the table `links` */

insert  into `links`(`id`,`name`,`created_at`,`description`,`group_id`) values (1,'Paint Protects WiFi Network from Hackers','2007-04-04 06:48:10','A company known as SEC Technologies has created a special type of paint that blocks Wi-Fi signals so that you can be sure hackers can ',1),(2,'Airplanes To Become WiFi Hotspots','2007-04-04 06:49:15','Airlines will start turning their airplanes into WiFi hotspots beginning early next year, WSJ reports. Here\'s what you need to know...',2),(3,'Planet VIP-195 GSM/WiFi Phone With Windows Messanger','2007-04-04 06:50:47','The phone does comply with IEEE 802.11b and IEEE 802.11g to provide phone capability via WiFi. As GSM phone the VIP-195 support 900/1800/1900 band and GPRS too. It comes with simple button to switch between WiFi or GSM mod',1);
