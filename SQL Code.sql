-- ============================================================
-- UK TRAINS — DATABASE SETUP & ANALYSIS
-- Description : UK railway data cleaning, normalization & analysis
-- Database    : SQL Server
-- ============================================================


-- ============================================================
-- SECTION 0: DATABASE CREATION
-- ============================================================

CREATE DATABASE UK_Trains;
GO

USE UK_Trains;
GO


-- ============================================================
-- SECTION 1: RAW DATA INSPECTION
-- ============================================================

-- Inspect column definitions of the imported raw table
EXEC sp_help 'railway';

-- Preview raw data
SELECT * FROM railway;


-- ============================================================
-- SECTION 2: FEATURE ENGINEERING ON RAW TABLE
-- ============================================================

-- 2a. Delay duration (handles overnight journeys via modulo 1440)
ALTER TABLE railway
ADD Delay_Minutes AS ((DATEDIFF(MINUTE, Arrival_Time, Actual_Arrival_Time) + 1440) % 1440);

-- 2b. Departure hour + time-of-day period (both as computed columns)
ALTER TABLE railway
ADD
    Departure_Hour AS DATEPART(HOUR, Departure_Time),
    Time_Period    AS (
        CASE
            WHEN DATEPART(HOUR, Departure_Time) BETWEEN 5  AND 11 THEN 'Morning'
            WHEN DATEPART(HOUR, Departure_Time) BETWEEN 12 AND 16 THEN 'Afternoon'
            WHEN DATEPART(HOUR, Departure_Time) BETWEEN 17 AND 21 THEN 'Evening'
            ELSE 'Night'
        END
    );

-- 2c. Scheduled journey duration (handles overnight wrap)
ALTER TABLE railway
ADD Scheduled_Duration AS (
    CASE
        WHEN DATEDIFF(MINUTE, Departure_Time, Arrival_Time) >= 0
        THEN DATEDIFF(MINUTE, Departure_Time, Arrival_Time)
        ELSE DATEDIFF(MINUTE, Departure_Time, Arrival_Time) + 1440
    END
);

-- 2d. Actual journey duration (handles overnight wrap)
ALTER TABLE railway
ADD Actual_Duration AS (
    CASE
        WHEN DATEDIFF(MINUTE, Departure_Time, Actual_Arrival_Time) >= 0
        THEN DATEDIFF(MINUTE, Departure_Time, Actual_Arrival_Time)
        ELSE DATEDIFF(MINUTE, Departure_Time, Actual_Arrival_Time) + 1440
    END
);


-- ============================================================
-- SECTION 3: DATA QUALITY CHECKS
-- ============================================================

-- 3a. NULL counts across every column
SELECT
    SUM(CASE WHEN Transaction_ID      IS NULL THEN 1 ELSE 0 END) AS Nulls_Transaction_ID,
    SUM(CASE WHEN Ticket_Type         IS NULL THEN 1 ELSE 0 END) AS Nulls_Ticket_Type,
    SUM(CASE WHEN Refund_Request      IS NULL THEN 1 ELSE 0 END) AS Nulls_Refund_Request,
    SUM(CASE WHEN Journey_Status      IS NULL THEN 1 ELSE 0 END) AS Nulls_Journey_Status,
    SUM(CASE WHEN Date_of_Purchase    IS NULL THEN 1 ELSE 0 END) AS Nulls_Date_of_Purchase,
    SUM(CASE WHEN Time_of_Purchase    IS NULL THEN 1 ELSE 0 END) AS Nulls_Time_of_Purchase,
    SUM(CASE WHEN Date_of_Journey     IS NULL THEN 1 ELSE 0 END) AS Nulls_Date_of_Journey,
    SUM(CASE WHEN Departure_Time      IS NULL THEN 1 ELSE 0 END) AS Nulls_Departure_Time,
    SUM(CASE WHEN Arrival_Time        IS NULL THEN 1 ELSE 0 END) AS Nulls_Arrival_Time,
    SUM(CASE WHEN Actual_Arrival_Time IS NULL THEN 1 ELSE 0 END) AS Nulls_Actual_Arrival_Time,
    SUM(CASE WHEN Departure_Station   IS NULL THEN 1 ELSE 0 END) AS Nulls_Departure_Station,
    SUM(CASE WHEN Arrival_Destination IS NULL THEN 1 ELSE 0 END) AS Nulls_Arrival_Destination,
    SUM(CASE WHEN Price               IS NULL THEN 1 ELSE 0 END) AS Nulls_Price,
    SUM(CASE WHEN Railcard            IS NULL THEN 1 ELSE 0 END) AS Nulls_Railcard,
    SUM(CASE WHEN Reason_for_Delay    IS NULL THEN 1 ELSE 0 END) AS Nulls_Reason_for_Delay,
    SUM(CASE WHEN Delay_Minutes       IS NULL THEN 1 ELSE 0 END) AS Nulls_Delay_Minutes
FROM railway;

-- 3b. Duplicate check on natural journey key
SELECT
    Departure_Station,
    Arrival_Destination,
    Date_of_Journey,
    Departure_Time,
    COUNT(*) AS Occurrences
FROM railway
GROUP BY
    Departure_Station,
    Arrival_Destination,
    Date_of_Journey,
    Departure_Time
HAVING COUNT(*) > 1
ORDER BY Occurrences DESC;

-- 3c. Journeys marked Delayed but with 0 delay minutes
SELECT * FROM railway
WHERE Journey_Status = 'Delayed' AND Delay_Minutes = 0;

-- 3d. Journeys with negative delay (data anomaly check)
SELECT * FROM railway
WHERE Delay_Minutes < 0;

-- 3e. Distribution of Reason_for_Delay values
SELECT
    Reason_for_Delay,
    COUNT(*) AS Count
FROM railway
GROUP BY Reason_for_Delay
ORDER BY Count DESC;

-- 3f. Departure station distribution
SELECT
    Departure_Station,
    COUNT(*) AS Count
FROM railway
WHERE Departure_Station IS NOT NULL
GROUP BY Departure_Station
ORDER BY Count DESC;

-- 3g. Arrival destination distribution
SELECT
    Arrival_Destination,
    COUNT(*) AS Count
FROM railway
WHERE Arrival_Destination IS NOT NULL
GROUP BY Arrival_Destination
ORDER BY Count DESC;

-- 3h. Price variation check (same ticket attributes, different prices)
SELECT
    Railcard,
    Ticket_Type,
    Ticket_Class,
    Departure_Hour,
    Route,
    COUNT(DISTINCT Price) AS Price_Variations
FROM railway
GROUP BY
    Railcard,
    Ticket_Type,
    Ticket_Class,
    Departure_Hour,
    Route
HAVING COUNT(DISTINCT Price) > 1;


-- ============================================================
-- SECTION 4: DATA CLEANING
-- ============================================================

-- 4a. Trim whitespace from all stored text columns
--     NOTE: computed columns (Time_Period, Departure_Hour, etc.) cannot be trimmed
UPDATE railway
SET
    Purchase_Type       = TRIM(Purchase_Type),
    Payment_Method      = TRIM(Payment_Method),
    Ticket_Type         = TRIM(Ticket_Type),
    Refund_Request      = TRIM(Refund_Request),
    Journey_Status      = TRIM(Journey_Status),
    Departure_Station   = TRIM(Departure_Station),
    Arrival_Destination = TRIM(Arrival_Destination),
    Railcard            = TRIM(Railcard),
    Reason_for_Delay    = TRIM(Reason_for_Delay),
    Ticket_Class        = TRIM(Ticket_Class);

-- 4b. Standardize Reason_for_Delay values
UPDATE railway SET Reason_for_Delay = 'Staffing' WHERE Reason_for_Delay = 'Staff Shortage';
UPDATE railway SET Reason_for_Delay = 'No Delay' WHERE Reason_for_Delay IS NULL;

-- 4c. Fix journey_status: Delayed journeys with 0 delay minutes -> On Time
UPDATE railway
SET Journey_Status = 'On Time'
WHERE Journey_Status = 'Delayed' AND Delay_Minutes = 0;

-- 4d. Standardize arrival destination names (fix abbreviations and typos)
UPDATE railway SET Arrival_Destination = 'Edinburgh Park'     WHERE Arrival_Destination = 'Edinburgh';
UPDATE railway SET Arrival_Destination = 'Didcot Parkway'     WHERE Arrival_Destination = 'Didcot';
UPDATE railway SET Arrival_Destination = 'Warrington Central' WHERE Arrival_Destination = 'Warrington';
UPDATE railway SET Arrival_Destination = 'Wakefield Westgate' WHERE Arrival_Destination = 'Wakefield';
UPDATE railway SET Arrival_Destination = 'WVH'                WHERE Arrival_Destination = 'WVJ'; -- Fix station code typo

-- 4e. Add Day_of_Departure column (derived from Date_of_Journey)
ALTER TABLE railway
ADD Day_of_Departure VARCHAR(255);

UPDATE railway
SET Day_of_Departure = DATENAME(WEEKDAY, Date_of_Journey);

-- 4f. Rebuild Route column as a clean concatenation
--     Drop the old imported route column first, then recreate it
ALTER TABLE railway DROP COLUMN Route;

ALTER TABLE railway
ADD Route VARCHAR(255);

UPDATE railway
SET Route = CONCAT(Departure_Station, ' -> ', Arrival_Destination);

-- 4g. Add refund eligibility status column
ALTER TABLE railway
ADD Eligibility_Status VARCHAR(255);

UPDATE railway
SET Eligibility_Status = CASE
    WHEN Journey_Status = 'Cancelled' THEN 'eligible (full refund)'
    WHEN Delay_Minutes  >= 30         THEN 'eligible (delay repay)'
    ELSE                                   'not eligible'
END;


-- ============================================================
-- SECTION 5: SCHEMA CREATION (Normalized Tables)
-- ============================================================
-- Creation order respects all foreign key dependencies:
--   Stations -> Routes -> Route_Stations -> Journeys -> Train_Transactions

-- 5a. Stations lookup table
CREATE TABLE Stations
(
    Station_ID   INT          IDENTITY(1,1) PRIMARY KEY,
    Station_Name VARCHAR(255) NOT NULL UNIQUE
);

-- 5b. Routes dimension table
CREATE TABLE Routes
(
    Route_ID             INT          IDENTITY(1,1) PRIMARY KEY,
    Route_Name           VARCHAR(255),
    Departure_Station_ID INT          NOT NULL,
    Arrival_Station_ID   INT          NOT NULL,

    FOREIGN KEY (Departure_Station_ID) REFERENCES Stations(Station_ID),
    FOREIGN KEY (Arrival_Station_ID)   REFERENCES Stations(Station_ID)
);

-- 5c. Route-Stations junction table
CREATE TABLE Route_Stations
(
    Route_ID     INT,
    Station_ID   INT,
    Station_Type VARCHAR(50),  -- 'Departure' or 'Arrival'

    PRIMARY KEY (Route_ID, Station_ID),
    FOREIGN KEY (Route_ID)   REFERENCES Routes(Route_ID),
    FOREIGN KEY (Station_ID) REFERENCES Stations(Station_ID)
);

-- 5d. Journeys fact table (one row per unique trip)
CREATE TABLE Journeys
(
    Journey_ID          INT          IDENTITY(1,1) PRIMARY KEY,
    Journey_Status      VARCHAR(255),
    Departure_Time      TIME,
    Arrival_Time        TIME,
    Actual_Arrival_Time TIME,
    Time_Period         VARCHAR(255),
    Reason_for_Delay    VARCHAR(255),
    Delay_Minutes       INT,
    Scheduled_Duration  INT,
    Actual_Duration     INT,
    Departure_Station   VARCHAR(255),
    Arrival_Destination VARCHAR(255),
    Day_of_Departure    VARCHAR(255),
    Date_of_Journey     DATE,
    Route_ID            INT,

    FOREIGN KEY (Route_ID) REFERENCES Routes(Route_ID)
);

-- 5e. Train_Transactions fact table (one row per ticket sold)
CREATE TABLE Train_Transactions
(
    Transaction_ID     VARCHAR(255)  PRIMARY KEY,
    Journey_ID         INT,
    Price              DECIMAL(10,2),
    Ticket_Class       VARCHAR(255),
    Ticket_Type        VARCHAR(255),
    Railcard           VARCHAR(255),
    Payment_Method     VARCHAR(255),
    Purchase_Type      VARCHAR(255),
    Date_of_Purchase   DATE,
    Refund_Request     VARCHAR(255),
    Eligibility_Status VARCHAR(255),

    FOREIGN KEY (Journey_ID) REFERENCES Journeys(Journey_ID)
);


-- ============================================================
-- SECTION 6: DATA POPULATION
-- ============================================================

-- 6a. Populate Stations (union of all departure and arrival station names)
INSERT INTO Stations (Station_Name)
SELECT DISTINCT Station_Name
FROM (
    SELECT Departure_Station   AS Station_Name FROM railway WHERE Departure_Station   IS NOT NULL
    UNION
    SELECT Arrival_Destination AS Station_Name FROM railway WHERE Arrival_Destination IS NOT NULL
) AS AllStations;

-- 6b. Populate Routes (distinct origin-destination pairs)
INSERT INTO Routes (Route_Name, Departure_Station_ID, Arrival_Station_ID)
SELECT DISTINCT
    r.Route,
    s1.Station_ID,
    s2.Station_ID
FROM railway r
    JOIN Stations s1 ON r.Departure_Station   = s1.Station_Name
    JOIN Stations s2 ON r.Arrival_Destination = s2.Station_Name;

-- 6c. Populate Route_Stations junction table
INSERT INTO Route_Stations (Route_ID, Station_ID, Station_Type)
SELECT Route_ID, Departure_Station_ID, 'Departure' FROM Routes;

INSERT INTO Route_Stations (Route_ID, Station_ID, Station_Type)
SELECT Route_ID, Arrival_Station_ID, 'Arrival' FROM Routes;

-- 6d. Populate Journeys (deduplicated by natural journey key)
INSERT INTO Journeys
(
    Journey_Status, Departure_Time, Arrival_Time, Actual_Arrival_Time,
    Time_Period, Reason_for_Delay, Delay_Minutes, Scheduled_Duration,
    Actual_Duration, Departure_Station, Arrival_Destination,
    Day_of_Departure, Date_of_Journey
)
SELECT
    Journey_Status, Departure_Time, Arrival_Time, Actual_Arrival_Time,
    Time_Period, Reason_for_Delay, Delay_Minutes, Scheduled_Duration,
    Actual_Duration, Departure_Station, Arrival_Destination,
    Day_of_Departure, Date_of_Journey
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY
                Departure_Station,
                Arrival_Destination,
                Date_of_Journey,
                Departure_Time
            ORDER BY (SELECT NULL)
        ) AS RowNumber
    FROM railway
) AS Deduplicated
WHERE RowNumber = 1;

-- 6e. Link each Journey row to its Route
UPDATE j
SET j.Route_ID = r.Route_ID
FROM Journeys j
    JOIN Stations s1 ON j.Departure_Station    = s1.Station_Name
    JOIN Stations s2 ON j.Arrival_Destination  = s2.Station_Name
    JOIN Routes   r  ON r.Departure_Station_ID = s1.Station_ID
                    AND r.Arrival_Station_ID   = s2.Station_ID;

-- 6f. Fix Journeys still marked Delayed with 0 delay minutes
UPDATE Journeys
SET Journey_Status = 'On Time'
WHERE Journey_Status = 'Delayed' AND Delay_Minutes = 0;

-- 6g. Populate Train_Transactions
--     Refund_Request is derived inline from Eligibility_Status (no separate UPDATE needed)
INSERT INTO Train_Transactions
(
    Transaction_ID, Journey_ID, Price, Ticket_Class, Ticket_Type, Railcard,
    Payment_Method, Purchase_Type, Date_of_Purchase, Refund_Request, Eligibility_Status
)
SELECT
    r.Transaction_ID,
    j.Journey_ID,
    r.Price,
    r.Ticket_Class,
    r.Ticket_Type,
    r.Railcard,
    r.Payment_Method,
    r.Purchase_Type,
    r.Date_of_Purchase,
    CASE
        WHEN r.Eligibility_Status IN ('eligible (full refund)', 'eligible (delay repay)')
        THEN 'Yes'
        ELSE 'No'
    END AS Refund_Request,
    r.Eligibility_Status
FROM railway r
    INNER JOIN Journeys j
        ON  r.Departure_Station   = j.Departure_Station
        AND r.Arrival_Destination = j.Arrival_Destination
        AND r.Date_of_Journey     = j.Date_of_Journey
        AND r.Departure_Time      = j.Departure_Time
WHERE r.Transaction_ID     IS NOT NULL
  AND r.Price              IS NOT NULL
  AND r.Ticket_Class       IS NOT NULL
  AND r.Ticket_Type        IS NOT NULL
  AND r.Railcard           IS NOT NULL
  AND r.Payment_Method     IS NOT NULL
  AND r.Purchase_Type      IS NOT NULL
  AND r.Date_of_Purchase   IS NOT NULL
  AND r.Eligibility_Status IS NOT NULL;


-- ============================================================
-- SECTION 7: VALIDATION
-- ============================================================

-- 7a. Unified view joining all normalized tables (used for reporting & checks)
CREATE VIEW Full_Railway_Data AS
SELECT
    t.Transaction_ID,
    s_dep.Station_Name  AS Departure_Station,
    s_arr.Station_Name  AS Arrival_Destination,
    j.Date_of_Journey,
    j.Departure_Time,
    j.Arrival_Time,
    j.Actual_Arrival_Time,
    j.Day_of_Departure,
    j.Time_Period,
    j.Journey_Status,
    j.Reason_for_Delay,
    j.Delay_Minutes,
    j.Scheduled_Duration,
    j.Actual_Duration,
    t.Price,
    t.Ticket_Class,
    t.Ticket_Type,
    t.Railcard,
    t.Payment_Method,
    t.Purchase_Type,
    t.Date_of_Purchase,
    t.Refund_Request,
    t.Eligibility_Status
FROM Train_Transactions t
    JOIN Journeys  j     ON t.Journey_ID          = j.Journey_ID
    JOIN Routes    r     ON j.Route_ID             = r.Route_ID
    JOIN Stations  s_dep ON r.Departure_Station_ID = s_dep.Station_ID
    JOIN Stations  s_arr ON r.Arrival_Station_ID   = s_arr.Station_ID;

-- 7b. Row count validation across all tables
SELECT COUNT(*) AS Total_Raw_Transactions FROM railway            WHERE Transaction_ID IS NOT NULL;
SELECT COUNT(*) AS Total_Normalized        FROM Full_Railway_Data;
SELECT COUNT(*) AS Total_Journeys          FROM Journeys;
SELECT COUNT(*) AS Total_Stations          FROM Stations;
SELECT COUNT(*) AS Total_Routes            FROM Routes;

-- 7c. Rows present in raw table but MISSING from normalized view
SELECT Transaction_ID, Price, Ticket_Class, Departure_Station
FROM railway
EXCEPT
SELECT Transaction_ID, Price, Ticket_Class, Departure_Station
FROM Full_Railway_Data;

-- 7d. Rows present in normalized view but MISSING from raw table
SELECT Transaction_ID, Price, Ticket_Class, Departure_Station
FROM Full_Railway_Data
EXCEPT
SELECT Transaction_ID, Price, Ticket_Class, Departure_Station
FROM railway;


-- ============================================================
-- SECTION 8: ANALYSIS QUERIES
-- ============================================================

-- ── TRANSACTIONS & REVENUE ──────────────────────────────────

-- Q1: Total Tickets Sold
SELECT COUNT(*) AS Total_Transactions
FROM Train_Transactions;

-- Q2: Average Ticket Price
SELECT AVG(Price) AS Avg_Price
FROM Train_Transactions;

-- Q3: Total Revenue
SELECT SUM(Price) AS Total_Revenue
FROM Train_Transactions;

-- Q4: Purchase Type Distribution
SELECT
    Purchase_Type,
    COUNT(*) AS Count
FROM Train_Transactions
GROUP BY Purchase_Type;

-- Q5: Payment Method Distribution
SELECT
    Payment_Method,
    COUNT(*) AS Count
FROM Train_Transactions
GROUP BY Payment_Method;

-- Q6: Ticket Class Distribution
SELECT
    Ticket_Class,
    COUNT(*) AS Count
FROM Train_Transactions
GROUP BY Ticket_Class;

-- Q7: Revenue by Ticket Type
SELECT
    Ticket_Type,
    SUM(Price) AS Revenue
FROM Train_Transactions
GROUP BY Ticket_Type
ORDER BY Revenue DESC;

-- Q8: Revenue by Ticket Class and Type (with % share of total)
SELECT
    Ticket_Class,
    Ticket_Type,
    COUNT(Transaction_ID)                                                        AS Total_Tickets_Sold,
    SUM(Price)                                                                   AS Total_Revenue,
    CAST(SUM(Price) * 100.0 / SUM(SUM(Price)) OVER () AS DECIMAL(5,2))          AS Revenue_Percentage
FROM Train_Transactions
GROUP BY Ticket_Class, Ticket_Type
ORDER BY Total_Revenue DESC;

-- Q9: Revenue by Railcard
SELECT
    Railcard,
    COUNT(Transaction_ID) AS Tickets_Sold,
    SUM(Price)            AS Total_Revenue,
    AVG(Price)            AS Average_Ticket_Price
FROM Train_Transactions
GROUP BY Railcard
ORDER BY Total_Revenue DESC;

-- Q10: Revenue by Purchase Type and Payment Method
SELECT
    Purchase_Type,
    Payment_Method,
    COUNT(Transaction_ID) AS Transaction_Count,
    SUM(Price)            AS Total_Revenue
FROM Train_Transactions
GROUP BY Purchase_Type, Payment_Method
ORDER BY Purchase_Type, Total_Revenue DESC;

-- Q11: Top Routes by Ticket Sales
SELECT
    s_dep.Station_Name AS Departure_Station,
    s_arr.Station_Name AS Arrival_Destination,
    COUNT(*)           AS Trips
FROM Train_Transactions t
    JOIN Journeys  j     ON t.Journey_ID          = j.Journey_ID
    JOIN Routes    r     ON j.Route_ID             = r.Route_ID
    JOIN Stations  s_dep ON r.Departure_Station_ID = s_dep.Station_ID
    JOIN Stations  s_arr ON r.Arrival_Station_ID   = s_arr.Station_ID
GROUP BY s_dep.Station_Name, s_arr.Station_Name
ORDER BY Trips DESC;

-- Q12: Ticket Sales and Revenue by Route
SELECT
    r.Route_Name,
    COUNT(t.Transaction_ID) AS Total_Tickets,
    SUM(t.Price)            AS Total_Revenue,
    AVG(j.Delay_Minutes)    AS Average_Delay_On_Route
FROM Routes r
    JOIN Journeys           j ON r.Route_ID   = j.Route_ID
    JOIN Train_Transactions t ON j.Journey_ID = t.Journey_ID
GROUP BY r.Route_Name
ORDER BY Total_Revenue DESC;

-- ── JOURNEY PERFORMANCE ─────────────────────────────────────

-- Q13: Journey Status Distribution
SELECT
    Journey_Status,
    COUNT(Journey_ID)                                                                                  AS Total_Journeys,
    CAST(COUNT(Journey_ID) * 100.0 / (SELECT COUNT(*) FROM Journeys) AS DECIMAL(5,2))                 AS Status_Percentage
FROM Journeys
GROUP BY Journey_Status
ORDER BY Total_Journeys DESC;

-- Q14: Top 10 Stations by Total Delay Minutes
SELECT TOP 10
    Departure_Station,
    COUNT(Journey_ID)  AS Delayed_Journeys_Count,
    AVG(Delay_Minutes) AS Average_Delay_Minutes,
    SUM(Delay_Minutes) AS Total_Delay_Minutes
FROM Journeys
WHERE Delay_Minutes > 0
GROUP BY Departure_Station
ORDER BY Total_Delay_Minutes DESC;

-- Q15: Delay Percentage by Route (routes with more than 10 trips)
SELECT
    Departure_Station,
    Arrival_Destination,
    COUNT(*)                                                                                                               AS Total_Trips,
    SUM(CASE WHEN Journey_Status <> 'On Time' THEN 1 ELSE 0 END)                                                           AS Disrupted_Trips,
    CAST(SUM(CASE WHEN Journey_Status <> 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))                  AS Delay_Percentage,
    AVG(CASE WHEN Delay_Minutes > 0 THEN Delay_Minutes ELSE NULL END)                                                       AS Avg_Delay_Minutes
FROM Journeys
GROUP BY Departure_Station, Arrival_Destination
HAVING COUNT(*) > 10
ORDER BY Delay_Percentage DESC, Avg_Delay_Minutes DESC;

-- Q16: Delay Rate by Day of Departure
SELECT
    Day_of_Departure,
    COUNT(*)                                                                                                    AS Total_Journeys,
    CAST(SUM(CASE WHEN Journey_Status = 'Delayed'   THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))    AS Delay_Rate,
    CAST(SUM(CASE WHEN Journey_Status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))    AS Cancellation_Rate,
    AVG(Delay_Minutes)                                                                                          AS Avg_Delay_Minutes
FROM Journeys
GROUP BY Day_of_Departure
ORDER BY Delay_Rate DESC;

-- Q17: Most Common Reasons for Delay
SELECT
    Reason_for_Delay,
    COUNT(Journey_ID)  AS Frequency_of_Delay,
    AVG(Delay_Minutes) AS Average_Delay_Time
FROM Journeys
WHERE Reason_for_Delay IS NOT NULL
  AND Reason_for_Delay <> 'No Delay'
GROUP BY Reason_for_Delay
ORDER BY Frequency_of_Delay DESC;

-- Q18: Journey Performance by Time Period
SELECT
    j.Time_Period,
    COUNT(*)                                                                                                    AS Total_Journeys,
    CAST(SUM(CASE WHEN j.Journey_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))    AS Delay_Rate,
    AVG(j.Delay_Minutes)                                                                                        AS Average_Delay_Minutes,
    SUM(t.Price)                                                                                                AS Total_Revenue
FROM Journeys j
    JOIN Train_Transactions t ON j.Journey_ID = t.Journey_ID
GROUP BY j.Time_Period
ORDER BY Total_Journeys DESC;

-- Q19: Revenue at Risk — Cancellation Loss Percentage of Total Revenue
SELECT
    SUM(CASE WHEN j.Journey_Status = 'Cancelled' THEN t.Price ELSE 0 END)        AS Cancelled_Revenue,
    SUM(t.Price)                                                                   AS Total_Revenue,
    CAST(
        SUM(CASE WHEN j.Journey_Status = 'Cancelled' THEN t.Price ELSE 0 END)
        * 100.0 / NULLIF(SUM(t.Price), 0)
    AS DECIMAL(5,2))                                                               AS Cancellation_Loss_Percentage
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID;

-- Q20: Refunded Tickets and Estimated Lost Revenue by Reason for Delay
SELECT
    j.Reason_for_Delay,
    COUNT(t.Transaction_ID) AS Refunded_Tickets,
    SUM(t.Price)            AS Estimated_Lost_Revenue
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
WHERE t.Eligibility_Status = 'eligible (delay repay)'
  AND j.Delay_Minutes > 0
GROUP BY j.Reason_for_Delay
ORDER BY Estimated_Lost_Revenue DESC;

-- ── BOOKING BEHAVIOUR ───────────────────────────────────────

-- Q21: Ticket Sales by Lead Time (Days Booked in Advance)
SELECT
    DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) AS Days_In_Advance,
    COUNT(t.Transaction_ID)                               AS Tickets_Sold,
    AVG(t.Price)                                          AS Average_Ticket_Price
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
WHERE t.Date_of_Purchase <= j.Date_of_Journey
GROUP BY DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey)
ORDER BY Days_In_Advance ASC;

-- Q22: Ticket Sales by Booking Window (grouped buckets)
SELECT
    CASE
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 0 AND  1 THEN '0-1 days'
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 2 AND  7 THEN '2-7 days'
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 8 AND 30 THEN '8-30 days'
        ELSE '30+ days'
    END AS Booking_Window,
    COUNT(t.Transaction_ID) AS Tickets_Sold,
    AVG(t.Price)            AS Average_Ticket_Price
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
WHERE t.Date_of_Purchase <= j.Date_of_Journey
GROUP BY
    CASE
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 0 AND  1 THEN '0-1 days'
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 2 AND  7 THEN '2-7 days'
        WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) BETWEEN 8 AND 30 THEN '8-30 days'
        ELSE '30+ days'
    END
ORDER BY MIN(DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey));

-- Q23: Average Lead Time by Ticket Type
SELECT
    Ticket_Type,
    AVG(DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey)) AS Avg_Lead_Time_Days
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
WHERE t.Date_of_Purchase <= j.Date_of_Journey
GROUP BY Ticket_Type;

-- Q24: Same-Day Purchase Percentage
SELECT
    CAST(
        SUM(CASE WHEN DATEDIFF(DAY, t.Date_of_Purchase, j.Date_of_Journey) = 0 THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(*), 0)
    AS DECIMAL(5,2)) AS Same_Day_Purchase_Percentage
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID;

-- ── STATION & TIME ANALYSIS ─────────────────────────────────

-- Q25: Busiest Stations by Hour of Day (ticket volume)
SELECT
    s.Station_Name,
    DATEPART(HOUR, j.Departure_Time) AS Hour_of_Day,
    COUNT(t.Transaction_ID)          AS Number_of_Tickets_Sold
FROM Stations s
    JOIN Route_Stations     rs ON s.Station_ID        = rs.Station_ID
    JOIN Journeys            j ON j.Departure_Station = s.Station_Name
    JOIN Train_Transactions  t ON t.Journey_ID        = j.Journey_ID
GROUP BY s.Station_Name, DATEPART(HOUR, j.Departure_Time)
ORDER BY Number_of_Tickets_Sold DESC;

-- Q26: Delay Rate by Departure Station
SELECT
    Departure_Station,
    COUNT(*)                                                                                                   AS Total_Trips,
    CAST(SUM(CASE WHEN Journey_Status <> 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))    AS Delay_Rate
FROM Journeys
GROUP BY Departure_Station
ORDER BY Delay_Rate DESC;

-- Q27: On-Time vs Delayed Ticket Counts by Departure Station
SELECT
    Departure_Station,
    COUNT(*)                                                      AS Total_Tickets_Sold,
    SUM(CASE WHEN Journey_Status = 'On Time' THEN 1 ELSE 0 END)  AS On_Time_Tickets,
    SUM(CASE WHEN Journey_Status = 'Delayed' THEN 1 ELSE 0 END)  AS Delayed_Tickets
FROM Journeys
GROUP BY Departure_Station
ORDER BY Total_Tickets_Sold DESC;

-- ── REFUNDS & FINANCIAL RISK ────────────────────────────────

-- Q28: Gross vs Net Revenue by Ticket Class (after refunds)
SELECT
    Ticket_Class,
    COUNT(*)                                                                   AS Total_Tickets_Sold,
    SUM(Price)                                                                 AS Gross_Revenue,
    COUNT(CASE WHEN Refund_Request = 'Yes' THEN 1 END)                        AS Refunded_Tickets,
    SUM(CASE WHEN Refund_Request = 'Yes' THEN Price ELSE 0 END)               AS Refunded_Revenue,
    SUM(Price) - SUM(CASE WHEN Refund_Request = 'Yes' THEN Price ELSE 0 END)  AS Net_Revenue
FROM Train_Transactions
GROUP BY Ticket_Class;

-- Q29: Cancellation Rate by Ticket Class
SELECT
    t.Ticket_Class,
    COUNT(*)                                                                                                          AS Tickets,
    SUM(t.Price)                                                                                                      AS Revenue,
    CAST(SUM(CASE WHEN j.Journey_Status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))         AS Cancellation_Rate
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
GROUP BY t.Ticket_Class;

-- Q30: Refund Impact by Route
SELECT
    r.Route_Name,
    COUNT(*)                                                         AS Total_Journeys,
    SUM(CASE WHEN t.Refund_Request = 'Yes' THEN 1    ELSE 0 END)    AS Refunded_Count,
    SUM(CASE WHEN t.Refund_Request = 'Yes' THEN t.Price ELSE 0 END) AS Refunded_Revenue
FROM Routes r
    JOIN Journeys           j ON r.Route_ID   = j.Route_ID
    JOIN Train_Transactions t ON j.Journey_ID = t.Journey_ID
GROUP BY r.Route_Name
ORDER BY Refunded_Revenue DESC;

-- Q31: Route Disruption Summary (Delayed + Cancelled combined)
SELECT
    r.Route_Name,
    COUNT(*)                                                                                                                            AS Total_Journeys,
    SUM(CASE WHEN j.Journey_Status IN ('Delayed', 'Cancelled') THEN 1 ELSE 0 END)                                                       AS Disrupted_Journeys,
    CAST(SUM(CASE WHEN j.Journey_Status IN ('Delayed', 'Cancelled') THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2))              AS Disruption_Rate,
    AVG(CASE WHEN j.Journey_Status = 'Delayed' THEN j.Delay_Minutes END)                                                                AS Avg_Delay_Minutes
FROM Journeys j
    JOIN Routes r ON j.Route_ID = r.Route_ID
GROUP BY r.Route_Name
ORDER BY Disrupted_Journeys DESC;

-- Q32: Advance vs Anytime Average Price by Route
SELECT
    j.Route_ID,
    AVG(CASE WHEN t.Ticket_Type = 'Advance' THEN t.Price END) AS Advance_Avg_Price,
    AVG(CASE WHEN t.Ticket_Type = 'Anytime' THEN t.Price END) AS Anytime_Avg_Price
FROM Train_Transactions t
    JOIN Journeys j ON t.Journey_ID = j.Journey_ID
GROUP BY j.Route_ID;

-- Q33: Monthly Performance Comparison by Route (Month-over-Month growth)
WITH MonthlyPerformance AS
(
    SELECT
        r.Route_Name,
        YEAR(j.Date_of_Journey)  AS Journey_Year,
        MONTH(j.Date_of_Journey) AS Journey_Month,
        COUNT(t.Transaction_ID)  AS Total_Tickets,
        SUM(t.Price)             AS Monthly_Revenue,
        ROUND(AVG(CAST(j.Delay_Minutes AS FLOAT)), 2) AS Avg_Delay
    FROM Journeys j
        JOIN Routes             r ON j.Route_ID   = r.Route_ID
        JOIN Train_Transactions t ON j.Journey_ID = t.Journey_ID
    GROUP BY r.Route_Name, YEAR(j.Date_of_Journey), MONTH(j.Date_of_Journey)
),
ComparisonTable AS
(
    SELECT
        Route_Name,
        Journey_Year,
        Journey_Month,
        Avg_Delay,
        Total_Tickets,
        LAG(Total_Tickets) OVER (PARTITION BY Route_Name ORDER BY Journey_Year, Journey_Month) AS Prev_Month_Tickets,
        LAG(Avg_Delay)     OVER (PARTITION BY Route_Name ORDER BY Journey_Year, Journey_Month) AS Prev_Month_Delay
    FROM MonthlyPerformance
)
SELECT
    Route_Name,
    Journey_Year,
    Journey_Month,
    CAST(Avg_Delay        AS DECIMAL(10,2)) AS Current_Avg_Delay,
    CAST(Prev_Month_Delay AS DECIMAL(10,2)) AS Prev_Month_Avg_Delay,
    Total_Tickets                            AS Current_Tickets,
    Prev_Month_Tickets,
    CAST(
        (Total_Tickets - Prev_Month_Tickets) * 100.0
        / NULLIF(Prev_Month_Tickets, 0)
    AS DECIMAL(10,2))                        AS Sales_Growth_Pct
FROM ComparisonTable
WHERE Prev_Month_Tickets IS NOT NULL
ORDER BY Route_Name, Journey_Year, Journey_Month;


-- ============================================================
-- END OF SCRIPT
-- ============================================================
