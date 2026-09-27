/**
 * 服务端统一配置
 *
 * 🔥 公网地址的唯一修改点：
 *   更换公网映射地址时，只需修改下面的 SERVER_HOST 一处，
 *   所有后端代码（图片、视频、安装包、背景图等 URL 拼接）均从此读取。
 *
 *   前端 Flutter 端对应修改 lib/config.dart 中的 baseUrl / wsUrl。
 */

// 公网访问地址（不带尾部斜杠）
// 例如：'http://zdxt.dpdns.org'  或  'http://123.456.789.012:3000'
const SERVER_HOST = 'http://zdxt.dpdns.org';

module.exports = { SERVER_HOST };
