SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for mostactive
-- ----------------------------
DROP TABLE IF EXISTS `mostactive`;
CREATE TABLE `mostactive`  (
  `playername` varchar(128) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `steamid` varchar(32) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `last_accountuse` int(64) NOT NULL,
  `timeCT` int(16) NULL DEFAULT NULL,
  `timeTT` int(16) NULL DEFAULT NULL,
  `timeSPE` int(16) NULL DEFAULT NULL,
  `total` int(16) NULL DEFAULT NULL,
  PRIMARY KEY (`steamid`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8 COLLATE = utf8_general_ci ROW_FORMAT = Dynamic;

SET FOREIGN_KEY_CHECKS = 1;
