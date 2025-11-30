// JXA script that interacts with System Events
var app = Application('System Events');
var processes = app.processes.whose({ name: 'Finder' });
processes.length > 0 ? "Finder is running" : "Finder is not running";
