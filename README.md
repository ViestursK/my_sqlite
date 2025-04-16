# Welcome to My Sqlite
***
testing home pc
## Task
The goal of this project is to build a lightweight SQLite-like database management system in Ruby. The challenge involves implementing SQL 
commands such as SELECT, INSERT, UPDATE, DELETE, and JOIN, all operating on CSV files instead of a traditional database.

## Description
This project solves the problem of interacting with CSV files in a structured and SQL-like manner. Using Ruby, the program interprets SQL 
commands provided by the user through a command-line interface (CLI). It performs operations such as querying, inserting, updating, deleting 
records, and joining tables. By leveraging the CSV library and custom parsing logic, the project mimics a database engine with full CRUD 
(Create, Read, Update, Delete) functionality and other database-like features such as sorting and filtering.

## Installation
1. Get the files (either download from gitea or you can use docode);
2. Make sure you have Ruby installed (2.7 or later, or if using docode it should be good to go).

## Usage
To use the CLI and interact with your CSV-based database, run the following command:

ruby my_sqlite_cli.rb 

You can then input SQL-like commands directly into the CLI:

Examples:

SELECT:
SELECT name, college FROM nba_player_data.csv WHERE college = 'Duke University' ORDER BY name ASC;

INSERT:
INSERT INTO nba_player_data (name, year_start, year_end, position, height, weight, birth_date, college) VALUES ('John Doe', '2024', '2026', 'G', '6-5', '210', 'March 14, 2000', 'Duke University');

UPDATE:
UPDATE nba_player_data SET position = 'PG' WHERE name = Matt Zunic;

DELETE:
DELETE FROM nba_player_data WHERE name = 'John Doe';

JOIN:
SELECT name, college FROM nba_player_data JOIN nba_players ON nba_player_data.name = nba_players.Player;

### The Core Team
Martins Jurkans and Viesturs Kalcenaus

<span><i>Made at <a href='https://qwasar.io'>Qwasar SV -- Software Engineering School</a></i></span>
<span><img alt='Qwasar SV -- Software Engineering School's Logo' src='https://storage.googleapis.com/qwasar-public/qwasar-logo_50x50.png' width='20px' /></span>
