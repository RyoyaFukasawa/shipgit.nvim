function formatDate(date) {
  const d = new Date(date);
  return d.toISOString().split("T")[0];
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function debounce(fn, delay) {
  let timer;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), delay);
  };
}

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

module.exports = { formatDate, capitalize, debounce, deepClone };
