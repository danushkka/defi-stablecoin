// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

contract MockMoreDscThanCollateral is ERC20Burnable, Ownable {
    error MockDsc__MustBeMoreThanZero();
    error MockDsc__AmountExceedsBalance();
    error MockDsc__CannotMintToAddressZero();

    address public mockAggregator;

    constructor(address initialOwner, address _mockAggregator)
        ERC20("MockMoreDscThanCollateral", "MockMoreDSC")
        Ownable(initialOwner)
    {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        MockV3Aggregator(mockAggregator).updateAnswer(0); // crash the price to 0

        if (_amount <= 0) revert MockDsc__MustBeMoreThanZero();
        if (balance < _amount) revert MockDsc__AmountExceedsBalance();

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) revert MockDsc__CannotMintToAddressZero();
        if (_amount <= 0) revert MockDsc__MustBeMoreThanZero();

        _mint(_to, _amount);
        return true;
    }
}
