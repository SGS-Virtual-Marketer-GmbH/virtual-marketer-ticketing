var gulp = require('gulp');
var Vinyl = require('vinyl');
var rename = require('gulp-rename');
var svgstore = require('gulp-svgstore');
var svgmin = require('gulp-svgmin');
var cheerio = require('cheerio');
var through2 = require('through2');
var path = require('path');

var iconsource = 'icons/*.svg'

// gulp-cheerio 1.0.0, inlined: it pinned cheerio 0.22 and with it lodash.pick,
// which has no fixed release. The cheerio object is kept on the file, which is
// what gulp-svgstore picks up when it is there.
function cheerioRun(run) {
  return through2.obj(function(file, encoding, callback) {
    if (file.isNull()) return callback(null, file);
    var $ = file.cheerio = file.cheerio || cheerio.load(file.contents.toString(), { xmlMode: true });
    run($, file);
    file.contents = Buffer.from($.xml());
    callback(null, file);
  });
}

function build() {
  return gulp
    .src(iconsource)
    .pipe(rename({prefix: 'icon-'}))
    .pipe(svgmin(function getOptions(file){
      var prefix = path.basename(
        file.relative,
        path.extname(file.relative)
      );
      return {
        plugins: [
          {
            removeViewBox: false,
            removeTitle: false,
            cleanupIDs: {
              prefix: prefix + '-',
              minify: true
            }
          },
        ],
        js2svg: {
          pretty: true,
        },
      }
    }))
    .pipe(cheerioRun(function ($) {
          // remove green-screen color
          $('[fill="#50E3C2"]').removeAttr('fill').parents('[fill="none"]').removeAttr('fill');
          $('[fill="#BD0FE1"]').attr('fill', 'currentColor').parents('[fill="none"]').removeAttr('fill');
          // color in Sketch changed slightly BD0FE1 -> BD10E0
          $('[fill="#BD10E0"]').attr('fill', 'currentColor').parents('[fill="none"]').removeAttr('fill');
    }))
    .pipe(svgstore())
    .pipe(through2.obj(function (file, encoding, cb) {
      // Side effect: generate app/assets/stylesheets/svg-dimensions.css with
      //  information about the available icon sizes.
      var $ = cheerio.load(file.contents.toString())
      var data = $('svg > symbol').map(function (_i, tag) {
        // cheerio 1.0 parses with parse5, which keeps SVG's own `viewBox`
        // casing; cheerio 0.22 lowercased every attribute.
        var viewBox = (tag.attribs.viewBox || tag.attribs.viewbox).split(" ")
        return [
          '.'+ $(this).attr('id') + ' {' +
            ' width: ' + viewBox[2] + 'px;' +
            ' height: ' + viewBox[3] + 'px; ' +
          '}'
        ];
      }).get();
      var cssFile = new Vinyl({
          path: '../../../app/assets/stylesheets/svg-dimensions.css',
          contents: Buffer.from(data.join("\n"))
      });
      this.push(cssFile);
      this.push(file);
      cb();
    }))
    .pipe(gulp.dest('./'));
}

exports.default = function(cb) {
  gulp.watch(iconsource, build);
  cb();
}
exports.build = build
