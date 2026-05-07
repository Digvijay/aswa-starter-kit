const out = document.getElementById('output');
const btn = document.getElementById('refresh');

async function load() {
  out.textContent = 'Loading...';
  try {
    const res = await fetch('/api/status');
    const data = await res.json();
    out.textContent = JSON.stringify(data, null, 2);
  } catch (err) {
    out.textContent = 'Error: ' + err.message;
  }
}

btn.addEventListener('click', load);
load();
