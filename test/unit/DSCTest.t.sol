// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {

    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    DecentralizedStableCoin dsc;
    address public USER = makeAddr("user");

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function setUp() public {
        dsc = new DecentralizedStableCoin(msg.sender);
    }

    ////////////////////////////////////
    /////////// CONSTRUCTOR ////////////
    ////////////////////////////////////

    function testConstructorSetsOwner() public {
        address expectedOwner = USER;
        DecentralizedStableCoin newDsc = new DecentralizedStableCoin(USER);
        assertEq(newDsc.owner(), expectedOwner);
    }

    ////////////////////////////////////
    /////////////// MINT ///////////////
    ////////////////////////////////////

    function testMintRevertsIfAddressZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__CannotMintToAddressZero.selector);
        dsc.mint(address(0), 99);
    }

    function testMintRevertsIfAmountIsTooSmall() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(this), 0);
    }

    function testMintRevertsIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, 99);
    }

    ////////////////////////////////////
    /////////////// BURN ///////////////
    ////////////////////////////////////

    function testBurnRevertsIfAmountExceedsBalance() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(99);
    }

    function testBurnRevertsIfAmountIsTooSmall() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testBurnRevertsIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.burn(99);
    }
}
