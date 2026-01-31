export function generateUniqueId() {
  var min = Math.ceil(0);
  var max = Math.floor(1000000000000000);
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
