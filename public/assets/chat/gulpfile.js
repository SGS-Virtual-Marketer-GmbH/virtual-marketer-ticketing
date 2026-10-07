var gulp = require('gulp');
var autoprefixer = require('gulp-autoprefixer');
const sass = require('gulp-sass')(require('sass'));
var concat = require('gulp-concat');
var coffeescript = require('coffeescript');
var eco = require('eco');
var path = require('path');
var through2 = require('through2');
var rename = require('gulp-rename');
var uglify = require('gulp-uglify');
var order = require("gulp-order");

// gulp-eco 0.0.2, inlined with the same output: the package dragged in
// gulp-util 2 and with it lodash.template, which has no fixed release.
function ecoTemplates(namespace) {
  return through2.obj(function(file, encoding, callback) {
    if (file.isNull() || file.extname !== '.eco') return callback(null, file);

    var name = path.basename(file.path, '.eco');
    var output = 'if (!window.' + namespace + ') {\n  window.' + namespace + ' = {};\n}\n' +
      'window.' + namespace + '["' + name + '"] = ' + eco.compile(file.contents.toString()) + ';' + '\n';
    file.contents = Buffer.from(output);
    file.extname = '.js';
    callback(null, file);
  });
}

// gulp-coffee 2.3.5, inlined: it dragged in gulp-util and merge 1, neither
// of which has a fixed release on that line. Same compiler (CoffeeScript 1),
// so the output is byte-identical.
function coffee(options) {
  return through2.obj(function(file, encoding, callback) {
    if (file.isNull()) return callback(null, file);
    var js;
    try {
      js = coffeescript.compile(file.contents.toString('utf8'), Object.assign({ filename: file.path }, options));
    } catch (err) {
      return callback(err);
    }
    file.contents = Buffer.from(js);
    file.extname = '.js';
    callback(null, file);
  });
}

function logError(err) {
  console.error(err.toString());
}

function css() {
  return gulp.src('chat.scss')
    .pipe(sass.sync().on('error', logError))
    .pipe(autoprefixer({
        cascade: false
    }))
    .pipe(gulp.dest('./'));
}


function js() {
  // gulp 5: files are added with src() in the middle of one pipeline;
  // merge-stream cut the streamx-based output off after the first files.
  return gulp.src('chat.coffee')
    .pipe(coffee({bare: true}).on('error', logError))
    .pipe(gulp.src('views/*.eco'))
    .pipe(ecoTemplates('zammadChatTemplates'))
    .pipe(gulp.src('purify.min.js'))
    .pipe(order([
      "views/*.js",
      "purify.min.js",
      "chat.js",
    ], {base: './'}))
    .pipe(concat('chat.js'))
    .pipe(gulp.dest('./'))
    .pipe(uglify())
    .pipe(rename({ extname: '.min.js' }))
    .pipe(gulp.dest('./'));
}


function no_jquery() {
  // gulp 5: files are added with src() in the middle of one pipeline;
  // merge-stream cut the streamx-based output off after the first files.
  return gulp.src('chat-no-jquery.coffee')
    .pipe(coffee({bare: true}).on('error', logError))
    .pipe(gulp.src('views/*.eco'))
    .pipe(ecoTemplates('zammadChatTemplates'))
    .pipe(gulp.src('purify.min.js'))
    .pipe(order([
      "views/*.js",
      "purify.min.js",
      "chat.js",
    ], {base: './'}))
    .pipe(concat('chat-no-jquery.js'))
    .pipe(gulp.dest('./'))
    .pipe(uglify())
    .pipe(rename({ extname: '.min.js' }))
    .pipe(gulp.dest('./'));
}

exports.default = function() {
  gulp.watch(['chat.scss'], css);
  gulp.watch(['chat.coffee', 'views/*.eco'], js);
  gulp.watch(['chat-no-jquery.coffee', 'views/*.eco'], no_jquery);
}

exports.build = gulp.parallel(js, no_jquery, css)
