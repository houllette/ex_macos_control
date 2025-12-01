// JXA script with intentional syntax error
function broken() {
  this is not valid javascript
  return "This will never execute";
}
broken();
