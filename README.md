
# Sr Data Analyst: Mana and Coins model


Below is a complex model of in-app items and currencies.

### Basic model

In a game, a user has a “mana” balance. Each mana is a fungible, atomic and consumable token.

Mana can be spent to perform an action (e.g. move forward). For simplicity let’s assume there is only one action in the game.. and we will refer to it henceforth as the “action”. 

User can hold infinite amount of mana in their mana balance.

Mana auto-recharges in the background up to a specific “capacity”. Once capacity is reached, the auto-recharging will stop. If balance becomes less than capacity in the future, mana recharging will immediately resume.

User cannot buy mana using real money directly. User can buy mana only using “coins”, which is a virtual in-game currency. Unlike mana, coins never “recharge”, they have to be earnt. They can be earnt as occasional gifts we give out to the user. User can also buy them using real money. When this happens, our game client side is informed of the transaction (success or not) via a call back. The payment processor (e.g. Apple’s App Store) also offer notifications if we provide them with a hook url to send to. Mana and coins are not sold individually, they are sold in bulk using several items (e.g. “Drops=13coins”, “Bag=60coins”, “Chest”, “Barrel”, the numbers are just example) each one with a fixed cost that we pre-agreed with the payment provider on.  

Coins can be used to upgrade the charging speed and/or the capacity. These are Level 1 each by default and can become level 2, 3 etc. Once upgraded, the upgrade is permanent. 

Coins can also be used to buy a charing boost, which is a booster to the charging speed that only lasts x minutes. E.g. a five minutes 2x boost will double the charging speed for 5 minutes.


### Inflation model

The cherry on top of this whole model is an inflation model. Everything above (almost) inflates exponentially based on the user’s progress in the game. We call this the user’s level. (How many game levels he completed). Here are few examples of how this model works:

Action: initially cost’s 3 mana per action. Then it costs 3 x L ^ c (L is the user’s level. c is an inflation constant set at 1.1). Since mana is atomic this has to be rounded. We will refer to this as m_a for later.

Charging speed: Doesn’t inflate by itself, requires user to upgrade it for it to increase. Cost of upgrade is 3 x L_CS ^ c (L_CS is the level of the charging speed). Mana per hour speed is calculated as (3 x L_CS ^ c) x c4 (c4 is a constant set at 1.5).

Capacity: is (3 x L_C ^ c) x c2 (L_C is the level of the capacity and c2 is a constant set at 30). Upgrade cost is (3 x L_C ^ 2c) coins.

Coins per dollar: the coins items (e.g. chest or barrel) have a fixed money cost, as we can’t dynamically change the cost with the payment provider, it is predefined. However, the amount of coins is inflated based on L. We call this coins per dollar (CPD). So if an item cost 5 dollars, it will have 5x CPD coins. CPD is calculated as c3 x m_a (c3 is 4.32). You can then use CPD to calculate how many coins a user will get for any purchasable item at any level.



### Payment gateways

Every purchase with real money is handled by a thrid-party Payment Gateway (PG). It is important to keep in mind that while we created our app’s client side, we don’t trust it. Our trusted environment is our servers/backend.

1. The transaction is initiated by our client-side (app). The PG UI will take over the screen and the user completes the txn directly there. Once it is completed the PG will do a callback to our app informing it of the transaction completion and returning the screen control to the app. Transactions as you can imagine can have multiple outcomes: cancelled (by the user), failed (ie. cancelled by PG), completed (all good)
2. Our app send the transaction to our backend. So our system record that transaction. This is not trusted, but recorded for records sake.
3. At the same time PG server will send direct notification to our server informing it of the transaction (server-to-server). This transaction is recorded and is trusted.
4. At the same time, we also run a job every x minutes to check if there are any transactions that our app claimed to happen but we didn’t receive a notification for, and if any are found we go and ask PG about them. We record the result response as a transaction in our db also. 
5. The above 3 types of transactions are all talking about a single actual transaction. They can also happen out of order due to delays in network etc, or go missing (e.g. we don’t receive one of them), or received multiple times (due to re-attempts of server to deliver a notification) despite being about a single actual transaction. So we see the amount potentially multiple times… but it shouldn’t affect the real balance

### System notes


1. Users are highly incentivised to “game the system” or cheat/hack. We want to ensure that is very difficult in our architecture and data flows.
2. The user base is considerable in size.
3. Our transactions table is write only. We don’t update/delete transactions. We write/insert only
4. All transactions (money, mana, etc) are written in one table, with a “type” column to define the what is being transacted



### Task 1:

Provide a sample transactions dataset to engineers to ensure they generate the data you need for this system. You can split that per operation or organise it in a way you prefer, but it should illustrate what data will be generated when users take certain actions detailed above.

You can also make notes of other data that you need to be stored in the system that you need.



### Task 2:

Define data validation/expectation rules for the above systems’ transactions. You can write those in plain English logic statements. 

What can go wrong? What are the week spots that we might need to harden or implement validations / checks on? How would you validate it?

Keep in mind that the app is imperfect, it could have bugs, the users could be trying to game the system, networking issues can happen… etc.



### Task 3:


What would be interesting product/financial/business metrics to look at here in this app? Define them, motivate them (why are they interesting) and decide how you’re going to formulate them. 

Are these metrics suitable for defining success / failure of the product or business?

How should each be communicated/presented and why? What insights might be drawn out of it or questions it could answer?




### Please make sure you:

* Push your files on a regular basis. If we can't see your process, thinking and progress we can't evaluate. Don't wait for things to be perfect/final before you push to this repo.. ensure you're pushing as you go.
* Please break down the project into 3-4 chunks, and create a PR for each. 
* When you’re done with a milestone, squash merge it into the next PR. E.g. you’re done with release1, squash merge release1 into release2. From that point on please continue working on release2. Don’t go back to release1 and change it! Any things you would like to fix, simply fix them in release2. Once it’s done, squash merge it into release3 etc…
* Please keep all your branches and PRs, no need to delete anything
* Merge the final branch into main branch
* Contribute directly to this repo (i.e. avoid creating fork)
* Feel free to include screenshot or screen recording, mind maps, or other formats if that’s your process and it helps you do your work, but you don't have to do something out of your usual process. Just saying additional files and formats are welcomed.
* Document your thinking (think loud) when it is possible
* Please include a guide/instructions for your reviewer

Let us know when you’re done!

Thanks and looking forwards for a brilliant submission!










