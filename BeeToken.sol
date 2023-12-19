// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BlackList is Ownable {
    event AddedBlackList(address indexed _user);

    event RemovedBlackList(address indexed _user);

    /////// Getter to allow the same blacklist to be used also by other contracts (including upgraded Tether) ///////
    function getBlackListStatus(address _maker) public view returns (bool) {
        return isBlackListed[_maker];
    }

    mapping(address => bool) public isBlackListed;

    function addBlackList(address _evilUser) public onlyOwner {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList(address _clearedUser) public onlyOwner {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }
}

contract BEE is ERC20, BlackList {
    error CallFailed();

    using SafeMath for uint256;

    mapping(address => bool) public whitelist;

    // pairs
    mapping(address => bool) public pairs;

    bool private swapSwitch = false;

    uint256 private constant DENOMINATOR = 100;

    uint256 public fee = 20;

    mapping(address => uint256) public frozen;

    mapping(address => bool) public isHandler;

    event Recycled(address tokenAddr, address destination, uint256 amount);

    event AddedWhiteList(address indexed _user);

    event RemovedWhiteList(address indexed _user);

    event AddedPair(address indexed _pair);

    event RemovedPair(address indexed _pair);

    constructor(uint256 initialSupply, address owner) ERC20("Bee Wallet", "BEE") {
        _mint(owner, initialSupply);
        _transferOwnership(owner);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // super._transfer check zero address
        require(amount > 0, "BEE: Transfer amount must be greater then zero");
        require(
            !isBlackListed[msg.sender],
            "BEE:The sender has been blacklisted"
        );

        _validateFrozenAmount(sender, amount);
        // whitelist without fee
        if (whitelist[sender] || whitelist[recipient]) {
            super._transfer(sender, recipient, amount);
        } else if (pairs[sender] || pairs[recipient]) {
            require(swapSwitch, "BEE: Swap paused.");
            uint256 amountFee = amount.mul(fee).div(DENOMINATOR);
            uint256 amountRecv = amount.sub(amountFee);
            super._transfer(sender, address(this), amountFee);
            super._transfer(sender, recipient, amountRecv);
        } else {
            // normal transfer
            super._transfer(sender, recipient, amount);
        }
    }

    function recycleToken(
        address tokenAddr,
        address destination,
        uint256 amount
    ) external onlyOwner {
        ERC20(tokenAddr).transfer(destination, amount);
        emit Recycled(tokenAddr, destination, amount);
    }

    function recycleTrx(
        address destination,
        uint256 amount
    ) external onlyOwner {
        (bool success, ) = destination.call{value: amount}("");
        if (!success) {
            revert CallFailed();
        }
        emit Recycled(address(0), destination, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function addWhitelist(address _evilUser) public onlyOwner {
        whitelist[_evilUser] = true;
        emit AddedWhiteList(_evilUser);
    }

    function removeWhiteList(address _clearedUser) public onlyOwner {
        whitelist[_clearedUser] = false;
        emit RemovedWhiteList(_clearedUser);
    }

    function addPair(address _pair) public onlyOwner {
        pairs[_pair] = true;
        emit AddedPair(_pair);
    }

    function removePair(address _pair) public onlyOwner {
        pairs[_pair] = false;
        emit RemovedPair(_pair);
    }

    function setSwapSwitch(bool _sw) public onlyOwner {
        swapSwitch = _sw;
    }

    function _validateFrozenAmount(
        address _sender,
        uint256 _amount
    ) private view {
        require(
            balanceOf(_sender) >= _amount.add(frozen[_sender]),
            "BEE:Balance is frozen"
        );
    }

    function setFrozenAmount(
        address _user,
        uint256 _amount
    ) external returns (bool) {
        _validateHandler();
        frozen[_user] = _amount;
        return true;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "BEE: forbidden");
    }
}
