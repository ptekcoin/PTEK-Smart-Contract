// SPDX-License-Identifier: GPL-3.0

pragma solidity = 0.8.19;

/// @title Smart Contract for Rental Income Wallet
/// @author Ladejavu
/// @notice pays weekly rental income bonus
/// @dev deployed by the Education Smart Contract

contract RentalIncomeWallet {
    /// deployer of the contract
    address immutable public owner;

    /// used for reentrancy guard
    bool internal locked;

    /// to protect against reentrancy attack
    modifier ReentrancyGuard {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    /// check the balance of this contract
    modifier hasBalance(uint amount) {
        require(address(this).balance >= amount, "insufficient balance in rental income wallet");
         _;
    }

    /// check the deployer of this contract
    modifier onlyOwner {
        require(msg.sender == owner, "you're not the owner!");
        _;
    }

    event Received(address, uint);
    event Sent(address, uint);
    
    /// sets the deployer of this contract as owner
    constructor() {
        owner = msg.sender;
    }

    /// receive PTEK
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// receive PTEK
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /// send PTEK from this contract
    /// @dev can only be called by the education smart contract
    /// @param to The address to send PTEK to
    /// @param amount PTEK to be sent from this wallet
    /// @return True if transfer of PTEK is successful
    function sendBalance(address payable to, uint amount) onlyOwner hasBalance(amount) ReentrancyGuard public returns (bool) {
        require(to != address(0), "invalid address");
        bool success = to.send(amount);
        require(success, "failed to send rental income balance");
        emit Sent(to, amount);
        return success;
    }

    /// get total balance of this contract
    /// @return contract balance
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}