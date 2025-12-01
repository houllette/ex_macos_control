// JXA script that uses arguments
function run(argv) {
  if (argv.length > 0) {
    return argv[0];
  } else {
    return "No arguments provided";
  }
}
