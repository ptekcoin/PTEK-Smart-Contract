// SPDX-License-Identifier: GPL-3.0

import "./RentalIncomeContract.sol";
import "./MaturityContract.sol";

pragma solidity = 0.8.19;

/// @title Smart Contract for Education Wallet
/// @author Ladejavu
/// @notice Pays rental income bonus on user's locked PTEK and releases PTEK after 3 years
/// @dev deploys the maturity and rental income smart contracts

contract EducationWallet {
    /// rental income wallet instance
    RentalIncomeWallet immutable public rentalIncomeWallet;

    /// maturtity wallet instance
    MaturityWallet immutable public maturityWallet;

    /// deployer of the contract
    address immutable public owner;

    /// rental income bonus interval
    uint constant internal paymentIntervel = 7 days;

    /// user eligibilty for rental income bonus 
    uint constant internal atleastOld = 6 days;

    /// to prevent block.timestamp manipulation
    uint constant internal delay = 1 hours;

    /// used for reentrancy guard
    bool internal locked;

    /// store user detail
    struct User {
        uint packageAmount;
        uint packageExchangeRate;
        uint balance;
        uint week;
        uint rentalIncomeValue;
        uint bonus;
        uint joiningDate;
        uint lastPaid;
        bool active;
    }
    
    mapping(address => User) private users;

    /// PTEK is received by contract
    event Received(address, uint);

    /// PTEK sent from contract
    event Sent(address, uint);

    /// rental income bonus percentage updated
    event RentalIncomeValueUpdated(address, uint);

    /// user is created
    event UserInitialised(address, uint256);

    /// user is deleted
    event UserDeactivated(address, uint256);

    /// exchange rate for purchased package is set
    event PackageExchangeRateSet(address, uint256);

    /// locked PTEK is released
    event PTEKUnlocked(address, uint);

    /// rental income bonus is paid
    event RentalIncomeBonusPaid(address, uint256);

    /// to protect against reentrancy attack
    modifier ReentrancyGuard {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    /// check the deployer of this contract
    modifier onlyOwner {
        require(msg.sender == owner, "this method can only be executed by the owner");
        _;
    }

    /// check if the user is not already created
    modifier newUser {
        require(users[msg.sender].active == false, "user already exists");
        _;
    }

    /// check if the user is already created
    modifier userExists(address user) {
        require(users[user].active == true, "unknown user");
        _;
    }

    /// check if weekly rental income bonus payment pre-conditions are met
    modifier canPayRentalIncome(address _user) {
        require(_user != address(0), "invalid address");
        User memory user = users[_user];
        require((block.timestamp >= user.joiningDate + atleastOld + delay && user.week == 1) || block.timestamp >= user.lastPaid + paymentIntervel + delay, "rental income bonus cannot be paid at this time!");
        require(user.week <= 156, "rental income bonus is already paid for 156 weeks");
        require(user.packageExchangeRate > 0, "exchange rate cannot be 0");
        _;
    }

    /// check if release of locked PTEK pre-conditions are met
    modifier canUnlockPTEk(address _user){
        require(_user != address(0), "invalid address");
        User memory user = users[_user];
        require(user.week == 157 &&  block.timestamp >= user.lastPaid + paymentIntervel + delay, "end of education contract time has not reached yet");
        require(user.packageExchangeRate > 0, "exchange rate cannot be 0");
        _;
    }

    /// upon deployment, sets the owner of this contract and deploys rental income and maturity smart contracts
    constructor() {
        owner = msg.sender;
        rentalIncomeWallet = new RentalIncomeWallet();  
        maturityWallet = new MaturityWallet();
    }
    
    /// receive PTEK
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }
    
    /// receive PTEK and create user
    receive() external payable {
        initUser(msg.sender, msg.value);
        emit Received(msg.sender, msg.value);
    }

    /// @notice creates user when PTEK is locked
    /// @param user The user's walllet address
    /// @param amount The purchased package amount in PTEK
    function initUser(address user, uint amount) newUser internal {
        users[user].packageAmount = amount;
        users[user].balance = amount; 
        users[user].bonus = 0;
        users[user].week = 1;
        users[user].active = true;
        users[user].rentalIncomeValue = 25;
        users[user].joiningDate = block.timestamp;
        users[user].lastPaid = block.timestamp;
        emit UserInitialised(user, users[user].joiningDate);
    }

    /// @notice set exchange rate for user's package at the time of purchase
    /// @dev can only be called by the deployer of this contract
    /// @param user The user's wallet address
    /// @param exchangeRateUSD The exchange rate when package was purchased
    function setExchangeRate(address user, uint exchangeRateUSD) userExists(user) onlyOwner external {
        require(users[user].packageExchangeRate == 0, "package exchange rate is already set");
        users[user].packageExchangeRate = exchangeRateUSD;
        emit PackageExchangeRateSet(user, exchangeRateUSD);
    }

    /// @notice deletes user after 3 years
    /// @param user The user's wallet address 
    function deactivateUser(address user) userExists(user) internal {
        delete users[user];
        emit UserDeactivated(user, block.timestamp);
    }

    /// @notice get total locked PTEK in this contract
    /// @return contract balance
    function totalBalance() public view returns (uint) {
        return address(this).balance;
    }

    /// @notice get user's detail
    /// @dev can only be called by the deployer of this contract
    /// @param user The user's wallet address
    /// @return user's detail
    function getUser(address user) onlyOwner userExists(user) public view returns (User memory) {
        return users[user];
    }

    /// @notice pays weekly rental income bonus for 156 weeks from rental income wallet
    /// @dev can only be called by the deployer of this contract
    /// @param _user The user's wallet address
    /// @param exchangeRateUSD The current exchange rate of PTEK 
    function payRentalIncome(address _user, uint exchangeRateUSD) onlyOwner userExists(_user) canPayRentalIncome(_user) ReentrancyGuard external {
        User memory user = users[_user];
        if (user.week == 53) {
            user.rentalIncomeValue = 26;
            emit RentalIncomeValueUpdated(_user, 26);
        }
        if (user.week == 105) {
            user.rentalIncomeValue = 27;
            emit RentalIncomeValueUpdated(_user, 27);
        }
        user.week++;
        user.lastPaid = block.timestamp;

        uint numerator = user.rentalIncomeValue * user.packageAmount * user.packageExchangeRate * 10000;
        uint denominator = exchangeRateUSD * 100 * 100 * 10000;
        uint amount =  numerator / denominator;
        bool success = rentalIncomeWallet.sendBalance(payable(_user), amount);
        if (success) {
            user.bonus+=amount;
            emit RentalIncomeBonusPaid(_user, block.timestamp);
        } 
        users[_user] = user;
    }

    /// releases locked PTEK after 3 years have passed 
    /// incase of PTEK depreciation, additional PTEK is paid from maturity wallet based on current exchange rate
    /// @notice releases the locked PTEK to user's wallet
    /// @dev can only be called by the deployer of this contract
    /// @dev deletes user
    /// @param _user The user's wallet address
    /// @param currentExchangeRate The current exchange rate of PTEK 
    function endOfSmartContract(address payable _user, uint currentExchangeRate) onlyOwner userExists(_user) canUnlockPTEk(_user) ReentrancyGuard external {
        User memory user = users[_user];
        uint userPackageAmount = user.packageAmount;
        uint amountToRelease = user.packageAmount; 
        if (currentExchangeRate < user.packageExchangeRate) {
            amountToRelease = (user.packageAmount * user.packageExchangeRate * 10000) / (currentExchangeRate * 10000);
        }
        uint maturityWalletAmount = amountToRelease - userPackageAmount;
        if (maturityWalletAmount > 0) {
           maturityWallet.sendBalance(_user, maturityWalletAmount); 
        }
        require(address(this).balance >= userPackageAmount, "insufficient balance in education wallet");
        bool success = _user.send(userPackageAmount);
        require(success, "release of locked amount has failed");
        deactivateUser(_user);
        emit PTEKUnlocked(_user, amountToRelease);
    }
}
