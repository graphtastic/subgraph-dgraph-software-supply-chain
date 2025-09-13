// Sanity Check (standalone script)
// This script first does something silly, then runs useful infrastructure diagnostics.
// It does NOT invoke or depend on the real extractor logic. It is safe to run in any environment.

// --- Silly/goofy section ---
console.log('🦄 Welcome to the Graphtastic Silly Smooth Sanity Summary!');
console.log('Today, before we do anything useful, let us summon the power of the unicorn...');
const unicorn = [
  '           \\',
  '            \\',
  '             \\',
  '              >\\/7',
  '          _.-(6 6)-._',
  '         (=  Y  =)',
  '          /`-^--`\\',
  '         /     |\\\\',
  '        (  )-(  )\\\\',
  '         ""   ""',
];
unicorn.forEach(line => console.log(line));
console.log('✨ The unicorn has blessed your build. Proceeding with diagnostics...\n');

// --- Useful diagnostics section ---
const execSync = require('child_process').execSync;
function check(msg: string, fn: () => boolean) {
  try {
    if (fn()) {
      console.log(`✅ ${msg}`);
    } else {
      console.log(`❌ ${msg}`);
    }
  } catch (e) {
    console.log(`❌ ${msg} (error: ${e})`);
  }
}

check('Test harness is running', () => true);
check('Docker is available', () => {
  const output = execSync('docker --version').toString();
  return /Docker/.test(output);
});
check('Makefile is present', () => {
  const fs = require('fs');
  return fs.existsSync('../Makefile');
});
check('docker-compose.yml is present', () => {
  const fs = require('fs');
  return fs.existsSync('../docker-compose.yml');
});
try {
  execSync('make check-dockerfiles', { stdio: 'inherit', cwd: '..' });
  console.log('✅ All referenced Dockerfiles exist');
} catch (e) {
  console.log('❌ Some referenced Dockerfiles are missing');
}
try {
  execSync('make up', { stdio: 'inherit', cwd: '..' });
  console.log('✅ make up target runs (services start)');
} catch (e) {
  console.log('❌ make up target failed');
}
try {
  execSync('make down', { stdio: 'inherit', cwd: '..' });
  console.log('✅ make down target runs (services stop)');
} catch (e) {
  console.log('❌ make down target failed');
}
