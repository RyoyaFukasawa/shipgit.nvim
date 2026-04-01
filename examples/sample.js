const express = require("express");
const app = express();

const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Routes
app.get("/", (req, res) => {
  res.json({ message: "Hello, shipgit!" });
});

app.get("/users", (req, res) => {
  const users = [
    { id: 1, name: "Alice", role: "admin" },
    { id: 2, name: "Bob", role: "user" },
    { id: 3, name: "Charlie", role: "user" },
  ];
  res.json(users);
});

app.post("/users", (req, res) => {
  const { name, role } = req.body;
  if (!name) {
    return res.status(400).json({ error: "Name is required" });
  }
  res.status(201).json({ id: Date.now(), name, role: role || "user" });
});

app.get("/users/:id", (req, res) => {
  const id = parseInt(req.params.id, 10);
  res.json({ id, name: "User " + id });
});

app.delete("/users/:id", (req, res) => {
  res.status(204).send();
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: "Internal Server Error" });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
